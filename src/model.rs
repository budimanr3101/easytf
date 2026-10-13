use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

pub const SCHEMA_VERSION: u32 = 1;
pub const TEMPLATE_VERSION: &str = "0.3.0";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Project {
    pub name: String,
    pub environments: BTreeMap<String, Environment>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Environment {
    #[serde(default)]
    pub backend: Backend,
    pub values: Values,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Backend {
    #[default]
    Local,
    S3 {
        bucket: String,
        key: String,
        region: String,
        #[serde(default = "yes")]
        use_lockfile: bool,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Values {
    pub aws_region: String,
    #[serde(default)]
    pub aws_profile: Option<String>,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
    #[serde(default)]
    pub instances: BTreeMap<String, Instance>,
    #[serde(default)]
    pub security_groups: BTreeMap<String, SecurityGroup>,
    #[serde(default)]
    pub load_balancers: BTreeMap<String, crate::lb::LoadBalancer>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Instance {
    pub name: String,
    pub ami_id: String,
    pub instance_type: String,
    pub subnet_id: String,
    #[serde(default)]
    pub existing_security_group_ids: Vec<String>,
    #[serde(default)]
    pub security_group_keys: Vec<String>,
    #[serde(default = "default_volume")]
    pub root_volume_gib: u32,
    #[serde(default)]
    pub associate_public_ip: bool,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
    #[serde(default)]
    pub configuration: BTreeMap<String, serde_json::Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct SecurityGroup {
    pub name: String,
    pub description: String,
    pub subnet_id: String,
    #[serde(default)]
    pub ingress: BTreeMap<String, Rule>,
    #[serde(default = "default_egress")]
    pub egress: BTreeMap<String, Rule>,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Rule {
    pub protocol: String,
    pub from_port: Option<u16>,
    pub to_port: Option<u16>,
    pub cidr_ipv4: String,
    pub description: String,
}

fn yes() -> bool {
    true
}
fn default_volume() -> u32 {
    20
}
pub fn default_egress() -> BTreeMap<String, Rule> {
    BTreeMap::from([(
        "all_ipv4".into(),
        Rule {
            protocol: "-1".into(),
            from_port: None,
            to_port: None,
            cidr_ipv4: "0.0.0.0/0".into(),
            description: "Allow outbound IPv4 traffic".into(),
        },
    )])
}

impl Default for Values {
    fn default() -> Self {
        Self {
            aws_region: "ap-southeast-3".into(),
            aws_profile: None,
            tags: BTreeMap::new(),
            instances: BTreeMap::new(),
            security_groups: BTreeMap::new(),
            load_balancers: BTreeMap::new(),
        }
    }
}

impl Default for Environment {
    fn default() -> Self {
        Self {
            backend: Backend::Local,
            values: Values::default(),
        }
    }
}

impl Project {
    pub fn empty(name: &str) -> Self {
        let mut env = Environment::default();
        env.values.tags = BTreeMap::from([
            ("env".into(), "dev".into()),
            ("project".into(), name.into()),
        ]);
        Self {
            name: name.into(),
            environments: BTreeMap::from([("dev".into(), env)]),
        }
    }

    pub fn demo() -> Self {
        let mut project = Self::empty("payment-service");
        for (name, instance_type) in [
            ("dev", "t3.micro"),
            ("staging", "t3.small"),
            ("prod", "t3.medium"),
        ] {
            let mut env = Environment::default();
            env.values
                .tags
                .insert("project".into(), project.name.clone());
            env.values.tags.insert("env".into(), name.into());
            env.values.instances.insert(
                "web_primary".into(),
                Instance {
                    name: format!("payment-web-{name}"),
                    ami_id: "ami-0123456789abcdef0".into(),
                    instance_type: instance_type.into(),
                    subnet_id: "subnet-0123456789abcdef0".into(),
                    existing_security_group_ids: vec!["sg-0123456789abcdef0".into()],
                    security_group_keys: vec![],
                    configuration: BTreeMap::new(),
                    root_volume_gib: 20,
                    associate_public_ip: false,
                    tags: BTreeMap::new(),
                },
            );
            project.environments.insert(name.into(), env);
        }
        project
    }

    pub fn validate(&self) -> Result<()> {
        validate_key(&self.name, "Project name")?;
        if self.environments.is_empty() {
            bail!("Select at least one environment");
        }
        let mut state_locations = BTreeSet::new();
        let mut environment_paths = BTreeSet::new();
        for (name, env) in &self.environments {
            validate_key(name, "Environment name")?;
            if !environment_paths.insert(name.to_ascii_lowercase()) {
                bail!("Environment names must also be distinct on case-insensitive filesystems");
            }
            if env.values.aws_region.trim().is_empty() {
                bail!("{name}: AWS region is required");
            }
            if let Backend::S3 {
                bucket,
                key,
                region,
                ..
            } = &env.backend
            {
                if bucket.trim().is_empty() || key.trim().is_empty() || region.trim().is_empty() {
                    bail!("{name}: S3 bucket, state key, and backend region are required");
                }
                if !state_locations.insert((bucket.clone(), key.clone())) {
                    bail!("{name}: duplicate S3 state location; each environment requires its own key");
                }
            }
            for (key, sg) in &env.values.security_groups {
                validate_key(key, "Security group key")?;
                aws_id(&sg.subnet_id, "subnet-")?;
                if sg.name.trim().is_empty() || sg.description.trim().is_empty() {
                    bail!("{name}/{key}: security group name and description are required");
                }
                for (rule_key, rule) in sg.ingress.iter().chain(sg.egress.iter()) {
                    validate_key(rule_key, "Rule key")?;
                    rule.validate()
                        .map_err(|e| anyhow::anyhow!("{name}/{key}/{rule_key}: {e}"))?;
                }
            }
            for (key, lb) in &env.values.load_balancers {
                validate_key(key, "Load balancer key")?;
                lb.validate(&env.values)
                    .map_err(|error| anyhow::anyhow!("{name}/{key}: {error}"))?;
            }
            for (key, instance) in &env.values.instances {
                validate_key(key, "Instance key")?;
                if instance.name.trim().is_empty() || instance.instance_type.trim().is_empty() {
                    bail!("{name}/{key}: instance name and type are required");
                }
                crate::config::validate_ec2(&instance.configuration)?;
                let enabled = |key: &str| {
                    instance
                        .configuration
                        .get(key)
                        .and_then(serde_json::Value::as_array)
                        .is_some_and(|v| !v.is_empty())
                };
                let eni_mode = enabled("primary_network_interface") || enabled("network_interface");
                if !instance.ami_id.is_empty() || !enabled("launch_template") {
                    aws_id(&instance.ami_id, "ami-")?;
                }
                if eni_mode
                    && (instance.associate_public_ip
                        || !instance.existing_security_group_ids.is_empty()
                        || !instance.security_group_keys.is_empty()
                        || instance
                            .configuration
                            .get("private_ip")
                            .is_some_and(|v| !v.is_null()))
                {
                    bail!("{name}/{key}: existing ENIs own their security groups and IPs. Clear EC2 SG references, public IP, and private_ip; the selected subnet remains VPC/subnet validation context");
                }
                aws_id(&instance.subnet_id, "subnet-")?;
                if instance.root_volume_gib == 0 {
                    bail!("{name}/{key}: root volume must be greater than zero");
                }
                if instance.existing_security_group_ids.is_empty()
                    && instance.security_group_keys.is_empty()
                    && !eni_mode
                    && !enabled("launch_template")
                {
                    bail!("{name}/{key}: select at least one security group");
                }
                for id in &instance.existing_security_group_ids {
                    aws_id(id, "sg-")?;
                }
                for sg in &instance.security_group_keys {
                    if !env.values.security_groups.contains_key(sg) {
                        bail!("{name}/{key}: linked security group '{sg}' does not exist in this environment");
                    }
                }
            }
        }
        Ok(())
    }
}

impl Rule {
    pub fn validate(&self) -> Result<()> {
        validate_cidr(&self.cidr_ipv4)?;
        match self.protocol.as_str() {
            "tcp" | "udp" => match (self.from_port, self.to_port) {
                (Some(from), Some(to)) if from <= to => {}
                _ => bail!("TCP/UDP rules need a valid port range"),
            },
            "-1" if self.from_port.is_none() && self.to_port.is_none() => {}
            "-1" => bail!("All-protocol rules must omit ports"),
            _ => bail!("Supported protocols: tcp, udp, -1"),
        }
        Ok(())
    }
}

pub fn validate_key(value: &str, label: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > 64
        || !value.as_bytes()[0].is_ascii_alphanumeric()
        || !value
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        bail!("{label} must start with a letter/number and contain only letters, numbers, '_' or '-' (max 64)");
    }
    Ok(())
}

pub fn aws_id(value: &str, prefix: &str) -> Result<()> {
    let suffix = value.strip_prefix(prefix).unwrap_or("");
    if ![8, 17].contains(&suffix.len()) || !suffix.bytes().all(|b| b.is_ascii_hexdigit()) {
        bail!("Expected an AWS ID such as {prefix}0123456789abcdef0");
    }
    Ok(())
}

pub fn validate_cidr(value: &str) -> Result<()> {
    let Some((ip, prefix)) = value.split_once('/') else {
        bail!("Enter an IPv4 CIDR, such as 10.0.0.0/16");
    };
    let address = ip
        .parse::<std::net::Ipv4Addr>()
        .map_err(|_| anyhow::anyhow!("Invalid IPv4 address"))?;
    let bits = prefix
        .parse::<u32>()
        .map_err(|_| anyhow::anyhow!("Invalid IPv4 prefix"))?;
    if bits > 32 {
        bail!("IPv4 prefix must be between 0 and 32");
    }
    let mask = if bits == 0 {
        0
    } else {
        u32::MAX << (32 - bits)
    };
    if u32::from(address) & !mask != 0 {
        bail!("CIDR must use a network address, not a host address");
    }
    Ok(())
}
