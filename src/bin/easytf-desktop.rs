//! One-shot JSON bridge for the native app. All Terraform logic stays in the shared engine.
use anyhow::{bail, Context, Result};
use easytf::{discovery, model::Project, project, render};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    io::{self, Read},
    path::PathBuf,
    sync::atomic::AtomicBool,
};

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    operation: String,
    root: Option<PathBuf>,
    project: Option<Project>,
    baseline: Option<Baseline>,
    kind: Option<String>,
    region: Option<String>,
    profile: Option<String>,
    subnet: Option<String>,
}
#[derive(serde::Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Baseline {
    project: Project,
    observed: std::collections::BTreeMap<String, String>,
    snapshot: std::collections::BTreeMap<String, String>,
}
impl From<project::Loaded> for Baseline {
    fn from(value: project::Loaded) -> Self {
        Self {
            project: value.project,
            observed: value.observed,
            snapshot: value.snapshot,
        }
    }
}
impl From<Baseline> for project::Loaded {
    fn from(value: Baseline) -> Self {
        Self {
            project: value.project,
            observed: value.observed,
            snapshot: value.snapshot,
        }
    }
}
fn run(request: Request) -> Result<Value> {
    match request.operation.as_str() {
        "schema" => Ok(serde_json::from_str(include_str!(
            "../../schemas/ec2-options.json"
        ))?),
        "example" => Ok(serde_json::to_value(Project::demo())?),
        "open" => {
            let loaded = project::load(&request.root.context("Choose a project folder")?)?;
            Ok(json!({"project":loaded.project, "baseline":Baseline::from(loaded)}))
        }
        "preview" | "publish" => {
            let root = request.root.context("Choose an output folder")?;
            if !root.is_absolute() {
                bail!("Choose an absolute output folder");
            }
            let model = request
                .project
                .context("Project configuration is required")?;
            model.validate()?;
            let loaded = request.baseline.map(project::Loaded::from);
            if let Some(old) = &loaded {
                let current = project::load(&root)?;
                if current.observed != old.observed {
                    bail!("Project files changed outside EasyTF. Reopen the project before generating.");
                }
            }
            let changes = project::changes(&root, &model)?;
            if request.operation == "publish" {
                let saved = project::publish(&root, &model, loaded.as_ref())?;
                Ok(
                    json!({"changes":changes,"baseline":Baseline::from(saved),"terraform_applied":false}),
                )
            } else {
                // This is a generation preview, never a Terraform execution plan.
                Ok(
                    json!({"changes":changes,"files":render::render(&model)?,"terraform_applied":false}),
                )
            }
        }
        "discover" => {
            let kind = match request.kind.as_deref() {
                Some("subnets") => discovery::Kind::Subnets,
                Some("security-groups") => discovery::Kind::SecurityGroups,
                Some("images") => discovery::Kind::Images,
                _ => bail!("Unsupported AWS picker"),
            };
            Ok(serde_json::to_value(discovery::discover(
                kind,
                &request.region.context("Choose an AWS region")?,
                request.profile.as_deref(),
                request.subnet.as_deref(),
                &AtomicBool::new(false),
            )?)?)
        }
        _ => bail!("Unsupported desktop operation"),
    }
}
fn main() {
    let result = (|| -> Result<Value> {
        let mut input = String::new();
        io::stdin()
            .take(16 * 1024 * 1024)
            .read_to_string(&mut input)?;
        run(serde_json::from_str(&input).context("Invalid desktop request")?)
    })();
    let envelope = match result {
        Ok(data) => json!({"ok":true,"data":data}),
        Err(error) => json!({"ok":false,"error":format!("{error:#}")}),
    };
    println!("{envelope}");
}
