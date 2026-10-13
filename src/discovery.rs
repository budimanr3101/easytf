use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::io::Read;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, clap::ValueEnum)]
pub enum Kind {
    Subnets,
    SecurityGroups,
    Images,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Item {
    pub id: String,
    pub label: String,
    pub vpc: Option<String>,
}

/// Read-only discovery through the user's AWS CLI credential chain.
pub fn discover(
    kind: Kind,
    region: &str,
    profile: Option<&str>,
    subnet: Option<&str>,
    cancel: &AtomicBool,
) -> Result<Vec<Item>> {
    if region.is_empty()
        || region.len() > 64
        || !region
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-')
        || region.starts_with('-')
    {
        bail!("Choose a valid AWS region before browsing");
    }
    if profile
        .is_some_and(|p| p.is_empty() || p.starts_with('-') || p.chars().any(char::is_control))
    {
        bail!("Choose a valid AWS profile name before browsing");
    }
    if matches!(kind, Kind::SecurityGroups) {
        crate::model::aws_id(subnet.unwrap_or(""), "subnet-")
            .context("Choose a valid subnet before browsing security groups")?;
    }
    if cancel.load(Ordering::Relaxed) {
        bail!("AWS discovery cancelled");
    }
    let mut cmd = Command::new("aws");
    cmd.args([
        "--region",
        region,
        "--output",
        "json",
        "--no-cli-pager",
        "--no-cli-auto-prompt",
        "--cli-connect-timeout",
        "5",
        "--cli-read-timeout",
        "15",
    ]);
    if let Some(profile) = profile {
        cmd.args(["--profile", profile]);
    }
    cmd.env("AWS_PAGER", "")
        .env("AWS_CLI_AUTO_PROMPT", "off")
        .env("AWS_MAX_ATTEMPTS", "2");
    cmd.arg("ec2");
    let vpc = if matches!(kind, Kind::SecurityGroups) {
        if let Some(subnet) = subnet.filter(|s| !s.is_empty()) {
            let mut lookup = Command::new("aws");
            lookup.args([
                "--region",
                region,
                "--output",
                "json",
                "--no-cli-pager",
                "--no-cli-auto-prompt",
                "--cli-connect-timeout",
                "5",
                "--cli-read-timeout",
                "15",
            ]);
            if let Some(profile) = profile {
                lookup.args(["--profile", profile]);
            }
            lookup
                .env("AWS_PAGER", "")
                .env("AWS_MAX_ATTEMPTS", "2")
                .args(["ec2", "describe-subnets", "--subnet-ids", subnet]);
            let value = execute(lookup, cancel)?;
            Some(
                value["Subnets"][0]["VpcId"]
                    .as_str()
                    .context("Selected subnet has no VPC")?
                    .to_owned(),
            )
        } else {
            bail!("Choose a subnet before browsing security groups")
        }
    } else {
        None
    };
    match kind {
        Kind::Subnets => {
            cmd.arg("describe-subnets");
        }
        Kind::SecurityGroups => {
            cmd.arg("describe-security-groups").args([
                "--filters",
                &format!("Name=vpc-id,Values={}", vpc.as_ref().unwrap()),
            ]);
        }
        Kind::Images => {
            cmd.args([
                "describe-images",
                "--owners",
                "amazon",
                "--filters",
                "Name=state,Values=available",
                "Name=name,Values=al2023-ami-2023*",
                "--max-items",
                "200",
            ]);
        }
    }
    parse(kind, &execute(cmd, cancel)?)
}

fn execute(mut cmd: Command, cancel: &AtomicBool) -> Result<Value> {
    // File-backed capture prevents pipe deadlocks while waiting/cancelling.
    let mut stdout = tempfile::tempfile()?;
    let mut stderr = tempfile::tempfile()?;
    let mut child = cmd
        .stdin(Stdio::null())
        .stdout(stdout.try_clone()?)
        .stderr(stderr.try_clone()?)
        .spawn()
        .context("AWS CLI is unavailable. Install AWS CLI v2 or enter IDs manually")?;
    let start = Instant::now();
    let status = loop {
        if cancel.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(45) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("AWS discovery cancelled or timed out. Manual input remains available");
        }
        if let Some(status) = child.try_wait()? {
            break status;
        }
        std::thread::sleep(Duration::from_millis(50));
    };
    use std::io::{Seek, SeekFrom};
    stdout.seek(SeekFrom::Start(0))?;
    stderr.seek(SeekFrom::Start(0))?;
    if !status.success() {
        let mut message = String::new();
        stderr.take(4096).read_to_string(&mut message)?;
        bail!("AWS discovery failed: {}. Check the selected profile, region, SSO session, and EC2 describe permissions", message.trim());
    }
    serde_json::from_reader(stdout).context("AWS CLI returned invalid JSON")
}

pub fn parse(kind: Kind, value: &Value) -> Result<Vec<Item>> {
    let (collection, id_key) = match kind {
        Kind::Subnets => ("Subnets", "SubnetId"),
        Kind::SecurityGroups => ("SecurityGroups", "GroupId"),
        Kind::Images => ("Images", "ImageId"),
    };
    let rows = value[collection]
        .as_array()
        .context("AWS response is missing its resource list")?;
    let mut ordered: Vec<_> = rows.iter().collect();
    if matches!(kind, Kind::Images) {
        ordered.sort_by(|a, b| b["CreationDate"].as_str().cmp(&a["CreationDate"].as_str()));
    }
    let mut items = Vec::new();
    for row in ordered {
        let id = row[id_key]
            .as_str()
            .context("AWS resource has no ID")?
            .to_owned();
        let name = row["Tags"]
            .as_array()
            .and_then(|tags| tags.iter().find(|t| t["Key"] == "Name"))
            .and_then(|t| t["Value"].as_str())
            .or_else(|| row["Name"].as_str())
            .or_else(|| row["GroupName"].as_str())
            .unwrap_or("unnamed");
        let details = match kind {
            Kind::Subnets => format!(
                "{} · {}",
                row["CidrBlock"].as_str().unwrap_or(""),
                row["AvailabilityZone"].as_str().unwrap_or("")
            ),
            Kind::SecurityGroups => row["VpcId"].as_str().unwrap_or("").into(),
            Kind::Images => format!(
                "{} · {}",
                row["Architecture"].as_str().unwrap_or(""),
                row["CreationDate"].as_str().unwrap_or("")
            ),
        };
        items.push(Item {
            id,
            label: format!("{name} · {details}"),
            vpc: row["VpcId"].as_str().map(str::to_owned),
        });
    }
    if !matches!(kind, Kind::Images) {
        items.sort_by(|a, b| a.label.cmp(&b.label));
    }
    Ok(items)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_network_metadata_and_rejects_invalid_responses() {
        let items = parse(Kind::Subnets, &serde_json::json!({"Subnets":[{"SubnetId":"subnet-01234567","VpcId":"vpc-01234567","CidrBlock":"10.0.0.0/24","AvailabilityZone":"ap-southeast-1a","Tags":[{"Key":"Name","Value":"private"}]}]})).unwrap();
        assert!(items[0].label.contains("private"));
        assert_eq!(items[0].vpc.as_deref(), Some("vpc-01234567"));
        assert!(parse(Kind::Images, &serde_json::json!({})).is_err());
    }
    #[cfg(unix)]
    #[test]
    fn cancellation_terminates_the_child_process() {
        let mut cmd = Command::new("/bin/sh");
        cmd.args(["-c", "exec sleep 5"]);
        let start = Instant::now();
        let result = execute(cmd, &AtomicBool::new(true));
        assert!(result.unwrap_err().to_string().contains("cancelled"));
        assert!(start.elapsed() < Duration::from_secs(2));
    }
}
