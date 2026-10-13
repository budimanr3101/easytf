use crate::model::{Backend, Project, SCHEMA_VERSION, TEMPLATE_VERSION};
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Metadata {
    pub schema_version: u32,
    pub template_version: String,
    pub name: String,
    pub environments: BTreeMap<String, String>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct S3Config {
    pub bucket: String,
    pub key: String,
    pub region: String,
    pub use_lockfile: bool,
}

pub fn render(project: &Project) -> Result<BTreeMap<String, String>> {
    project.validate()?;
    let metadata = Metadata {
        schema_version: SCHEMA_VERSION,
        template_version: TEMPLATE_VERSION.into(),
        name: project.name.clone(),
        environments: project
            .environments
            .iter()
            .map(|(name, env)| {
                (
                    name.clone(),
                    match env.backend {
                        Backend::Local => "local",
                        Backend::S3 { .. } => "s3",
                    }
                    .into(),
                )
            })
            .collect(),
    };
    let mut files = BTreeMap::from([
        (".easytf.toml".into(), toml::to_string_pretty(&metadata)?),
        (".gitignore".into(), ".terraform/\n*.tfstate\n*.tfstate.*\n*.tfplan\ncrash.log\ncrash.*.log\n.easytf.lock\n.easytf/transaction.json\n.easytf/last-generated.json\n.easytf-stage-*/\n".into()),
        ("modules/load-balancer/main.tf".into(), include_str!("../templates/load-balancer/main.tf").into()),
        ("modules/load-balancer/variables.tf".into(), include_str!("../templates/load-balancer/variables.tf").into()),
        ("modules/load-balancer/outputs.tf".into(), include_str!("../templates/load-balancer/outputs.tf").into()),
        ("modules/load-balancer/versions.tf".into(), MODULE_VERSIONS.into()),
        ("modules/ec2/main.tf".into(), EC2_MAIN.into()),
        ("modules/ec2/variables.tf".into(), EC2_VARIABLES.into()),
        ("modules/ec2/outputs.tf".into(), EC2_OUTPUTS.into()),
        ("modules/ec2/versions.tf".into(), MODULE_VERSIONS.into()),
        ("modules/security-group/main.tf".into(), SG_MAIN.into()),
        ("modules/security-group/variables.tf".into(), SG_VARIABLES.into()),
        ("modules/security-group/outputs.tf".into(), SG_OUTPUTS.into()),
        ("modules/security-group/versions.tf".into(), MODULE_VERSIONS.into()),
    ]);
    for (name, env) in &project.environments {
        let prefix = format!("environments/{name}");
        for (file, content) in [
            ("main.tf", ROOT_MAIN),
            ("variables.tf", ROOT_VARIABLES),
            ("providers.tf", PROVIDER),
            ("versions.tf", ROOT_VERSIONS),
            ("outputs.tf", ROOT_OUTPUTS),
        ] {
            let content = match file {
                "main.tf" => format!(
                    "{}\n{}",
                    content,
                    include_str!("../templates/load-balancer/root.tf")
                ),
                "variables.tf" => format!(
                    "{}\n{}",
                    content,
                    include_str!("../templates/load-balancer/root-variables.tf")
                ),
                "outputs.tf" => format!(
                    "{}\n{}",
                    content,
                    include_str!("../templates/load-balancer/root-outputs.tf")
                ),
                _ => content.into(),
            };
            files.insert(format!("{prefix}/{file}"), content);
        }
        files.insert(
            format!("{prefix}/terraform.tfvars"),
            format_input(&env.values)?,
        );
        let backend = match &env.backend {
            Backend::Local => "terraform {\n  backend \"local\" {}\n}\n",
            Backend::S3 {
                bucket,
                key,
                region,
                use_lockfile,
            } => {
                files.insert(
                    format!("{prefix}/backend.s3.tfbackend"),
                    format_input(&S3Config {
                        bucket: bucket.clone(),
                        key: key.clone(),
                        region: region.clone(),
                        use_lockfile: *use_lockfile,
                    })?,
                );
                "terraform {\n  backend \"s3\" {}\n}\n"
            }
        };
        files.insert(format!("{prefix}/backend.tf"), backend.into());
    }
    let mut readme = format!("# {}\n\nGenerated with EasyTF {}.\n\n## Configuration\n\nEdit each environment's `terraform.tfvars` to change resource values.\nReopen this project with `easytf --project .`; the TUI reads those values.\nEnvironment tags apply to managed resources; per-resource tag maps are overrides.\nAn empty resource tag map still inherits environment tags.\nThe sample/demo IDs are placeholders and must be replaced with real AWS IDs.\n\n", project.name, TEMPLATE_VERSION);
    readme.push_str("## Terraform commands\n\nRun commands from the selected environment directory. AWS credentials use your\nstandard profile/SSO/environment configuration; credentials are not generated.\n\n");
    for (name, env) in &project.environments {
        let init = if matches!(env.backend, Backend::S3 { .. }) {
            "terraform init -backend-config=backend.s3.tfbackend"
        } else {
            "terraform init"
        };
        readme.push_str(&format!("### {name}\n\n```sh\ncd environments/{name}\n{init}\nterraform validate\nterraform plan\nterraform output -json\n```\n\n"));
    }
    readme.push_str("## Ownership and scope\n\nSubnet IDs and existing security group IDs use AWS data sources. They are read\nwithout adopting their infrastructure lifecycle. Security groups declared in\n`security_groups` and EC2 instances declared in `instances` are managed resources.\nModule outputs connect new resources and expose instance/network information.\nALB/NLB target attachments depend on EC2 IDs/private IPs and target group ARNs.\nLB/TG creation can run in parallel with EC2; attachment keys stay known during plan.\n\nS3 backend buckets must already exist. Backend migration, arbitrary Terraform\nproject adoption, imports, and Terraform apply are outside this MVP.\nUse Ctrl+B on subnet, AMI, and existing SG fields for explicit read-only AWS discovery.\nThe SG/VPC precondition supports security groups in their primary VPC;\nadditional VPC associations are outside this MVP. Default root volumes are encrypted gp3; optional root disk/launch-template configuration can override storage.\nEC2 optional settings live under each instance configuration object in tfvars.\ninstance_role generates a profile for an existing role; iam_instance_profile references a profile directly.\nNew SGs have no ingress until rules are supplied; outbound IPv4 is explicit.\n\nEasyTF checks local HCL and input consistency. AWS existence, permissions,\nAMI compatibility, routing, and deployability require Terraform/AWS checks.\nEasyTF never executes Terraform apply or destroy.\n\nGenerated `.tf` files are protected against manual overwrites. Input `.tfvars`\nand backend values are read back; their formatting is canonicalized on generation.\nKeep `.easytf.toml` and `.terraform.lock.hcl` in version control.\nLocal conflict snapshots are ignored by Git. On a fresh clone, existing generated\nfiles must match this template before updates can be published.\n");
    files.insert("README.md".into(), readme);
    for (path, content) in &files {
        if path.ends_with(".tf") || path.ends_with(".tfvars") || path.ends_with(".tfbackend") {
            hcl::parse(content)
                .map_err(|e| anyhow::anyhow!("Invalid generated HCL in {path}: {e}"))?;
        }
    }
    Ok(files)
}

pub const ROOT_VERSIONS: &str = include_str!("../templates/root_versions.tf");
const MODULE_VERSIONS: &str = include_str!("../templates/module_versions.tf");
const PROVIDER: &str = include_str!("../templates/provider.tf");
const ROOT_MAIN: &str = include_str!("../templates/root_main.tf");
const ROOT_VARIABLES: &str = include_str!("../templates/root_variables.tf");
const ROOT_OUTPUTS: &str = include_str!("../templates/root_outputs.tf");
const EC2_MAIN: &str = include_str!("../templates/ec2_main.tf");
const EC2_VARIABLES: &str = include_str!("../templates/ec2_variables.tf");
const EC2_OUTPUTS: &str = include_str!("../templates/ec2_outputs.tf");
const SG_MAIN: &str = include_str!("../templates/sg_main.tf");
const SG_VARIABLES: &str = include_str!("../templates/sg_variables.tf");
const SG_OUTPUTS: &str = include_str!("../templates/sg_outputs.tf");

/// Canonical literal input formatting without spawning Terraform. Multi-line
/// objects/arrays separate scalar alignment groups, matching Terraform's formatter.
pub fn format_input(value: &impl Serialize) -> Result<String> {
    let raw = hcl::to_string(value)?;
    let lines: Vec<&str> = raw.lines().collect();
    let mut output = Vec::with_capacity(lines.len());
    let mut index = 0;
    while index < lines.len() {
        let Some((indent, left, _)) = scalar_assignment(lines[index]) else {
            output.push(lines[index].to_string());
            index += 1;
            continue;
        };
        let mut end = index + 1;
        let mut max_width = left.len();
        while end < lines.len() {
            match scalar_assignment(lines[end]) {
                Some((other_indent, key, _)) if other_indent == indent => {
                    max_width = max_width.max(key.len());
                    end += 1;
                }
                _ => break,
            }
        }
        for line in &lines[index..end] {
            let (_, key, value) = scalar_assignment(line).unwrap();
            output.push(format!(
                "{indent}{key}{} = {value}",
                " ".repeat(max_width - key.len())
            ));
        }
        index = end;
    }
    Ok(output.join("\n") + "\n")
}

fn scalar_assignment(line: &str) -> Option<(&str, &str, &str)> {
    let indent_end = line.len() - line.trim_start().len();
    let mut quoted = false;
    let mut escaped = false;
    for (position, c) in line.char_indices().skip_while(|(i, _)| *i < indent_end) {
        if escaped {
            escaped = false;
            continue;
        }
        if quoted && c == '\\' {
            escaped = true;
            continue;
        }
        if c == '"' {
            quoted = !quoted;
            continue;
        }
        if !quoted && c == '=' {
            let value = line[position + 1..].trim();
            if value == "{" || value == "[" {
                return None;
            }
            return Some((
                &line[..indent_end],
                line[indent_end..position].trim(),
                value,
            ));
        }
    }
    None
}
