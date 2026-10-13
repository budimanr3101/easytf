use crate::model::{Backend, Environment, Project, Values, SCHEMA_VERSION, TEMPLATE_VERSION};
use crate::render::{render, Metadata, S3Config};
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::BTreeMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Component, Path, PathBuf};

const SNAPSHOT: &str = ".easytf/last-generated.json";
const JOURNAL: &str = ".easytf/transaction.json";

#[derive(Debug, Clone)]
pub struct Loaded {
    pub project: Project,
    pub observed: BTreeMap<String, String>,
    pub snapshot: BTreeMap<String, String>,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct Snapshot {
    hashes: BTreeMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Journal {
    pid: u32,
    originals: BTreeMap<String, Option<Vec<u8>>>,
    after_hashes: BTreeMap<String, String>,
    stage: String,
}

#[derive(Debug, Clone, Serialize)]
pub struct Change {
    pub path: String,
    pub action: &'static str,
    pub before: Option<String>,
    pub after: String,
}

pub fn load(root: &Path) -> Result<Loaded> {
    reject_symlinks(root, JOURNAL)?;
    if root.join(JOURNAL).exists() {
        bail!("An interrupted publish needs recovery. Run `easytf recover --project {}` before opening this project", root.display());
    }
    reject_symlinks(root, ".easytf.toml")?;
    let metadata: Metadata = toml::from_str(&fs::read_to_string(root.join(".easytf.toml"))
        .context("This folder is not an EasyTF project. Choose a new output folder; arbitrary Terraform project adoption is outside this MVP.")?)?;
    if metadata.schema_version != SCHEMA_VERSION
        || !matches!(
            metadata.template_version.as_str(),
            TEMPLATE_VERSION | "0.1.0"
        )
    {
        bail!("Unsupported project schema/template version; automatic template migration is not supported");
    }
    let mut project = Project {
        name: metadata.name,
        environments: BTreeMap::new(),
    };
    for (name, kind) in metadata.environments {
        crate::model::validate_key(&name, "Environment name")?;
        let vars = format!("environments/{name}/terraform.tfvars");
        reject_symlinks(root, &vars)?;
        let values: Values = hcl::from_str(&fs::read_to_string(root.join(&vars))?)
            .with_context(|| format!("Cannot load {vars}; unsupported fields/expressions are kept on disk and must be resolved before editing in EasyTF"))?;
        let backend = match kind.as_str() {
            "local" => Backend::Local,
            "s3" => {
                let path = format!("environments/{name}/backend.s3.tfbackend");
                reject_symlinks(root, &path)?;
                let config: S3Config = hcl::from_str(&fs::read_to_string(root.join(path))?)?;
                Backend::S3 {
                    bucket: config.bucket,
                    key: config.key,
                    region: config.region,
                    use_lockfile: config.use_lockfile,
                }
            }
            _ => bail!("Unsupported backend '{kind}'"),
        };
        project
            .environments
            .insert(name, Environment { backend, values });
    }
    project.validate()?;
    let files = render(&project)?;
    let mut observed = BTreeMap::new();
    for path in files.keys().chain(std::iter::once(&SNAPSHOT.to_string())) {
        reject_symlinks(root, path)?;
        if root.join(path).exists() {
            observed.insert(path.clone(), hash(&fs::read(root.join(path))?));
        }
    }
    let snapshot = if root.join(SNAPSHOT).exists() {
        serde_json::from_str::<Snapshot>(&fs::read_to_string(root.join(SNAPSHOT))?)?.hashes
    } else {
        BTreeMap::new()
    };
    Ok(Loaded {
        project,
        observed,
        snapshot,
    })
}

pub fn changes(root: &Path, project: &Project) -> Result<Vec<Change>> {
    let files = render(project)?;
    files
        .into_iter()
        .map(|(path, after)| {
            reject_symlinks(root, &path)?;
            let before = match fs::read_to_string(root.join(&path)) {
                Ok(value) => Some(value),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(error) => return Err(error.into()),
            };
            let action = match &before {
                None => "add",
                Some(value) if *value == after => "unchanged",
                Some(_) => "update",
            };
            Ok(Change {
                path,
                action,
                before,
                after,
            })
        })
        .collect()
}

pub fn publish(root: &Path, project: &Project, loaded: Option<&Loaded>) -> Result<Loaded> {
    project.validate()?;
    if let Some(old) = loaded {
        for (name, env) in &old.project.environments {
            let Some(new) = project.environments.get(name) else {
                bail!("Removing environment '{name}' is outside this MVP; its infrastructure/state must be handled explicitly");
            };
            if env.backend != new.backend {
                bail!("Backend changes require an explicit Terraform migration/reconfiguration workflow; EasyTF has preserved the project");
            }
        }
    }
    let files = render(project)?;
    if !root.exists() {
        fs::create_dir_all(root)?;
    }
    reject_symlinks(root, ".easytf.lock")?;
    let _lock = ProjectLock::acquire(root)?;
    if root.join(JOURNAL).exists() {
        bail!(
            "An interrupted publish needs `easytf recover --project {}`",
            root.display()
        );
    }
    if loaded.is_none()
        && fs::read_dir(root)?.any(|entry| {
            entry
                .map(|e| e.file_name() != ".easytf.lock")
                .unwrap_or(true)
        })
    {
        bail!("Output folder is not empty. Open it with --project if it is an EasyTF project, or choose a new folder");
    }
    for (path, after) in &files {
        reject_symlinks(root, path)?;
        if let Some(old) = loaded {
            let current = read_optional(&root.join(path))?;
            let digest = current.as_deref().map(hash);
            if digest.as_ref() != old.observed.get(path) {
                bail!("{path} changed after this project was loaded. Reopen it before publishing; no files were changed");
            }
            if !is_input(path) {
                if let Some(current) = current {
                    let tracked = old.snapshot.get(path);
                    let unmodified = tracked
                        .map(|expected| *expected == hash(&current))
                        .unwrap_or_else(|| current == after.as_bytes());
                    if !unmodified {
                        bail!("Generated file '{path}' has manual edits. EasyTF preserved it; automatic merging is outside this MVP");
                    }
                }
            }
        }
    }
    if let Some(old) = loaded {
        let current = read_optional(&root.join(SNAPSHOT))?.as_deref().map(hash);
        if current.as_ref() != old.observed.get(SNAPSHOT) {
            bail!("Project snapshot changed after loading; reopen the project before publishing");
        }
    }
    // Stage complete output before publishing; back up each changed file for rollback.
    let stage = tempfile::Builder::new()
        .prefix(".easytf-stage-")
        .tempdir_in(root)?;
    let snapshot = Snapshot {
        hashes: files
            .iter()
            .map(|(path, text)| (path.clone(), hash(text.as_bytes())))
            .collect(),
    };
    let mut all_files = files;
    all_files.insert(SNAPSHOT.into(), serde_json::to_string_pretty(&snapshot)?);
    let mut originals = BTreeMap::new();
    for (path, text) in &all_files {
        reject_symlinks(root, path)?;
        let staged = stage.path().join(path);
        fs::create_dir_all(staged.parent().unwrap())?;
        let mut file = fs::File::create(&staged)?;
        file.write_all(text.as_bytes())?;
        file.sync_all()?;
        originals.insert(path.clone(), read_optional(&root.join(path))?);
    }
    let journal = Journal {
        pid: std::process::id(),
        originals: originals.clone(),
        after_hashes: all_files
            .iter()
            .map(|(path, text)| (path.clone(), hash(text.as_bytes())))
            .collect(),
        stage: stage.path().file_name().unwrap().to_string_lossy().into(),
    };
    let journal_path = root.join(JOURNAL);
    reject_symlinks(root, JOURNAL)?;
    fs::create_dir_all(journal_path.parent().unwrap())?;
    let mut journal_file = fs::File::create(&journal_path)?;
    journal_file.write_all(serde_json::to_string(&journal)?.as_bytes())?;
    journal_file.sync_all()?;
    let mut written: Vec<String> = vec![];
    let result: Result<()> = (|| {
        for (path, text) in &all_files {
            if originals[path].as_deref() == Some(text.as_bytes()) {
                continue;
            }
            let destination = root.join(path);
            fs::create_dir_all(destination.parent().unwrap())?;
            fs::rename(stage.path().join(path), destination)?;
            written.push(path.clone());
        }
        Ok(())
    })();
    if let Err(error) = result {
        let mut failures = vec![];
        for path in written.into_iter().rev() {
            let restored = match &originals[&path] {
                Some(bytes) => fs::write(root.join(&path), bytes),
                None => fs::remove_file(root.join(&path)),
            };
            if let Err(error) = restored {
                failures.push(format!("{path}: {error}"));
            }
        }
        if !failures.is_empty() {
            bail!("Publish failed: {error}. Rollback incomplete: {}. Run easytf recover for this project", failures.join("; "));
        }
        fs::remove_file(&journal_path)?;
        return Err(error.context("Publish failed; file changes were rolled back"));
    }
    fs::remove_file(journal_path)?;
    load(root)
}

/// Explicitly restore an interrupted publication after its owning process exits.
/// Files changed independently since the interruption are preserved and block recovery.
pub fn recover(root: &Path) -> Result<usize> {
    reject_symlinks(root, ".easytf.lock")?;
    reject_symlinks(root, JOURNAL)?;
    if let Some(lock) = read_optional(&root.join(".easytf.lock"))? {
        let pid: u32 = String::from_utf8(lock)?
            .trim()
            .parse()
            .context("Invalid project lock")?;
        if process_alive(pid)? {
            bail!("EasyTF process {pid} is still running; recovery was not started");
        }
    }
    let Some(bytes) = read_optional(&root.join(JOURNAL))? else {
        if root.join(".easytf.lock").exists() {
            fs::remove_file(root.join(".easytf.lock"))?;
        }
        return Ok(0);
    };
    let journal: Journal =
        serde_json::from_slice(&bytes).context("Cannot read recovery journal")?;
    if process_alive(journal.pid)? {
        bail!(
            "EasyTF process {} is still running; recovery was not started",
            journal.pid
        );
    }
    for (path, before) in &journal.originals {
        if !managed_path(path) {
            bail!("Journal contains an unsupported file path '{path}'");
        }
        reject_symlinks(root, path)?;
        let current = read_optional(&root.join(path))?;
        let unchanged = current == *before;
        let generated = current.as_deref().map(hash).as_ref() == journal.after_hashes.get(path);
        if !unchanged && !generated {
            bail!("'{path}' changed independently after interruption. Recovery preserved it and stopped");
        }
    }
    for (path, before) in &journal.originals {
        let target = root.join(path);
        match before {
            Some(bytes) => {
                fs::create_dir_all(target.parent().unwrap())?;
                let mut restored = tempfile::NamedTempFile::new_in(target.parent().unwrap())?;
                restored.write_all(bytes)?;
                restored.as_file_mut().sync_all()?;
                restored.persist(&target).map_err(|e| e.error)?;
            }
            None if target.exists() => fs::remove_file(target)?,
            None => {}
        }
    }
    if journal.stage.starts_with(".easytf-stage-")
        && Path::new(&journal.stage).components().count() == 1
    {
        reject_symlinks(root, &journal.stage)?;
        let stage = root.join(&journal.stage);
        if stage.is_dir() {
            fs::remove_dir_all(stage)?;
        }
    }
    fs::remove_file(root.join(JOURNAL))?;
    if root.join(".easytf.lock").exists() {
        fs::remove_file(root.join(".easytf.lock"))?;
    }
    Ok(journal.originals.len())
}

fn managed_path(path: &str) -> bool {
    if matches!(path, ".easytf.toml" | ".gitignore" | "README.md" | SNAPSHOT) {
        return true;
    }
    let parts: Vec<_> = path.split('/').collect();
    match parts.as_slice() {
        ["modules", "ec2" | "security-group", "main.tf" | "variables.tf" | "outputs.tf" | "versions.tf"] => {
            true
        }
        ["environments", name, "main.tf"
        | "variables.tf"
        | "outputs.tf"
        | "versions.tf"
        | "providers.tf"
        | "backend.tf"
        | "terraform.tfvars"
        | "backend.s3.tfbackend"] => crate::model::validate_key(name, "Environment").is_ok(),
        _ => false,
    }
}

fn process_alive(pid: u32) -> Result<bool> {
    if pid == 0 || pid > i32::MAX as u32 {
        bail!("Invalid recovery process identity");
    }
    #[cfg(unix)]
    {
        // Signal zero only checks existence; it does not signal or terminate a process.
        let result = unsafe { libc::kill(pid as i32, 0) };
        Ok(result == 0 || std::io::Error::last_os_error().raw_os_error() != Some(libc::ESRCH))
    }
    #[cfg(not(unix))]
    {
        bail!("Recovery process checks are currently supported on macOS/Linux")
    }
}

pub fn save_draft(
    path: &Path,
    project: &Project,
    output: &Path,
    loaded: Option<&Loaded>,
) -> Result<()> {
    #[derive(Serialize)]
    struct Draft<'a> {
        project: &'a Project,
        output: &'a Path,
        baseline: Option<&'a BTreeMap<String, String>>,
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let parent = path.parent().unwrap_or_else(|| Path::new("."));
    let mut file = tempfile::NamedTempFile::new_in(parent)?;
    file.write_all(
        serde_json::to_string_pretty(&Draft {
            project,
            output,
            baseline: loaded.map(|l| &l.observed),
        })?
        .as_bytes(),
    )?;
    file.as_file_mut().sync_all()?;
    file.persist(path).map_err(|e| e.error)?;
    Ok(())
}

pub fn load_draft(path: &Path) -> Result<(Project, PathBuf)> {
    #[derive(Deserialize)]
    struct Draft {
        project: Project,
        output: PathBuf,
        baseline: Option<BTreeMap<String, String>>,
    }
    let draft: Draft = serde_json::from_str(&fs::read_to_string(path)?)?;
    if let Some(baseline) = &draft.baseline {
        for (relative, expected) in baseline {
            reject_symlinks(&draft.output, relative)?;
            let current = read_optional(&draft.output.join(relative))?
                .as_deref()
                .map(hash)
                .unwrap_or_default();
            if &current != expected {
                bail!("Project changed since the draft was created: {relative}. Open the current project instead");
            }
        }
    } else if draft.output.join(".easytf.toml").exists() {
        bail!("The draft destination now contains a generated project. Open it instead");
    }
    Ok((draft.project, draft.output))
}

pub fn hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn is_input(path: &str) -> bool {
    path.ends_with("/terraform.tfvars") || path.ends_with(".tfbackend")
}

fn read_optional(path: &Path) -> Result<Option<Vec<u8>>> {
    match fs::read(path) {
        Ok(bytes) => Ok(Some(bytes)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error.into()),
    }
}

fn reject_symlinks(root: &Path, relative: &str) -> Result<()> {
    if fs::symlink_metadata(root).is_ok_and(|m| m.file_type().is_symlink()) {
        bail!("Project root must not be a symbolic link");
    }
    let mut path = root.to_path_buf();
    for component in Path::new(relative).components() {
        if !matches!(component, Component::Normal(_)) {
            bail!("Unsafe generated path '{relative}'");
        }
        path.push(component);
        if fs::symlink_metadata(&path).is_ok_and(|m| m.file_type().is_symlink()) {
            bail!("Refusing to read/write symbolic link {}", path.display());
        }
    }
    Ok(())
}

struct ProjectLock {
    path: PathBuf,
}
impl ProjectLock {
    fn acquire(root: &Path) -> Result<Self> {
        let path = root.join(".easytf.lock");
        let mut file = OpenOptions::new().write(true).create_new(true).open(&path)
            .context("Project is locked by another EasyTF operation. If that process has exited, remove the stale .easytf.lock file before retrying")?;
        writeln!(file, "{}", std::process::id())?;
        Ok(Self { path })
    }
}
impl Drop for ProjectLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}
