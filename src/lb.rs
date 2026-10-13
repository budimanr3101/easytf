use crate::{
    config::Node,
    model::{aws_id, validate_key, Values},
};
use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct LoadBalancer {
    pub name: String,
    pub load_balancer_type: String,
    #[serde(default)]
    pub internal: bool,
    pub subnet_ids: Vec<String>,
    #[serde(default)]
    pub existing_security_group_ids: Vec<String>,
    #[serde(default)]
    pub security_group_keys: Vec<String>,
    #[serde(default)]
    pub deletion_protection: bool,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
    #[serde(default)]
    pub target_groups: BTreeMap<String, TargetGroup>,
    #[serde(default)]
    pub listeners: BTreeMap<String, Listener>,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct TargetGroup {
    pub port: u16,
    pub protocol: String,
    pub target_type: String,
    #[serde(default)]
    pub instance_keys: Vec<String>,
    #[serde(default)]
    pub existing_target_ids: Vec<String>,
    #[serde(default)]
    pub health_check: HealthCheck,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct HealthCheck {
    pub protocol: String,
    pub port: String,
    pub path: Option<String>,
    pub matcher: Option<String>,
    pub interval: u16,
    pub timeout: u16,
    pub healthy_threshold: u16,
    pub unhealthy_threshold: u16,
}
impl Default for HealthCheck {
    fn default() -> Self {
        Self {
            protocol: "HTTP".into(),
            port: "traffic-port".into(),
            path: Some("/".into()),
            matcher: Some("200".into()),
            interval: 30,
            timeout: 5,
            healthy_threshold: 3,
            unhealthy_threshold: 3,
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Listener {
    pub port: u16,
    pub protocol: String,
    pub target_group_key: String,
    pub certificate_arn: Option<String>,
    pub ssl_policy: Option<String>,
}

impl LoadBalancer {
    pub fn new(name: String, network: bool) -> Self {
        let protocol = if network { "TCP" } else { "HTTP" };
        let health = if network {
            HealthCheck {
                protocol: "TCP".into(),
                path: None,
                matcher: None,
                ..HealthCheck::default()
            }
        } else {
            HealthCheck::default()
        };
        Self {
            name,
            load_balancer_type: if network { "network" } else { "application" }.into(),
            internal: false,
            subnet_ids: vec![],
            existing_security_group_ids: vec![],
            security_group_keys: vec![],
            deletion_protection: false,
            tags: BTreeMap::new(),
            target_groups: BTreeMap::from([(
                "web".into(),
                TargetGroup {
                    port: 80,
                    protocol: protocol.into(),
                    target_type: "instance".into(),
                    instance_keys: vec![],
                    existing_target_ids: vec![],
                    health_check: health,
                    tags: BTreeMap::new(),
                },
            )]),
            listeners: BTreeMap::from([(
                "frontend".into(),
                Listener {
                    port: 80,
                    protocol: protocol.into(),
                    target_group_key: "web".into(),
                    certificate_arn: None,
                    ssl_policy: None,
                },
            )]),
        }
    }
    pub fn validate(&self, values: &Values) -> Result<()> {
        let application = match self.load_balancer_type.as_str() {
            "application" => true,
            "network" => false,
            _ => bail!("Choose application (ALB) or network (NLB)"),
        };
        if self.name.is_empty()
            || self.name.len() > 32
            || self.name.starts_with('-')
            || self.name.ends_with('-')
            || self.name.starts_with("internal-")
            || !self
                .name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '-')
        {
            bail!("Load balancer name must use letters/numbers/hyphens, max 32, and cannot start internal-");
        }
        if self.subnet_ids.len() < if application { 2 } else { 1 } {
            bail!("ALB requires at least two subnets in different AZs; NLB requires at least one");
        }
        unique(&self.subnet_ids, "LB subnets")?;
        for id in &self.subnet_ids {
            aws_id(id, "subnet-")?;
        }
        if application
            && self.existing_security_group_ids.is_empty()
            && self.security_group_keys.is_empty()
        {
            bail!("ALB needs at least one security group");
        }
        for id in &self.existing_security_group_ids {
            aws_id(id, "sg-")?;
        }
        for key in &self.security_group_keys {
            if !values.security_groups.contains_key(key) {
                bail!("Load balancer references missing managed SG '{key}'");
            }
        }
        if self.target_groups.is_empty() || self.listeners.is_empty() {
            bail!("Configure at least one target group and listener");
        }
        for (key, group) in &self.target_groups {
            validate_key(key, "Target group key")?;
            if group.port == 0
                || !if application {
                    ["HTTP", "HTTPS"].contains(&group.protocol.as_str())
                } else {
                    ["TCP", "TLS", "UDP", "TCP_UDP"].contains(&group.protocol.as_str())
                }
            {
                bail!("Target group '{key}': invalid port/protocol for this load balancer type");
            }
            if !["instance", "ip"].contains(&group.target_type.as_str()) {
                bail!("Target group supports instance or ip targets");
            }
            unique(&group.instance_keys, "EC2 target keys")?;
            unique(&group.existing_target_ids, "Existing targets")?;
            for instance in &group.instance_keys {
                if !values.instances.contains_key(instance) {
                    bail!("Target group '{key}' references missing EC2 key '{instance}'");
                }
            }
            for id in &group.existing_target_ids {
                if group.target_type == "instance" {
                    aws_id(id, "i-")?;
                } else {
                    id.parse::<std::net::Ipv4Addr>()
                        .map_err(|_| anyhow::anyhow!("IP targets require IPv4 addresses"))?;
                }
            }
            let health = &group.health_check;
            if !["HTTP", "HTTPS", "TCP"].contains(&health.protocol.as_str())
                || (application && health.protocol == "TCP")
            {
                bail!("Target group '{key}': invalid health check protocol");
            }
            if health.protocol == "TCP" && (health.path.is_some() || health.matcher.is_some()) {
                bail!("TCP health checks must leave path and matcher unset");
            }
            if health.protocol != "TCP"
                && health
                    .path
                    .as_ref()
                    .is_none_or(|path| !path.starts_with('/'))
            {
                bail!("HTTP(S) health checks require a path starting with /");
            }
            if health.port != "traffic-port"
                && health.port.parse::<u16>().ok().is_none_or(|p| p == 0)
            {
                bail!("Health check port must be traffic-port or 1–65535");
            }
            if !(5..=300).contains(&health.interval)
                || !(2..=120).contains(&health.timeout)
                || health.timeout >= health.interval
                || !(2..=10).contains(&health.healthy_threshold)
                || !(2..=10).contains(&health.unhealthy_threshold)
            {
                bail!("Invalid health check timing/thresholds");
            }
        }
        let mut ports = BTreeSet::new();
        for (key, listener) in &self.listeners {
            validate_key(key, "Listener key")?;
            if listener.port == 0 || !ports.insert(listener.port) {
                bail!("Listeners require unique nonzero ports");
            }
            if !if application {
                ["HTTP", "HTTPS"].contains(&listener.protocol.as_str())
            } else {
                ["TCP", "TLS", "UDP", "TCP_UDP"].contains(&listener.protocol.as_str())
            } {
                bail!("Invalid listener protocol");
            }
            let group = self
                .target_groups
                .get(&listener.target_group_key)
                .ok_or_else(|| {
                    anyhow::anyhow!("Listener '{key}' references a missing target group")
                })?;
            if ["HTTPS", "TLS"].contains(&listener.protocol.as_str()) {
                if listener
                    .certificate_arn
                    .as_ref()
                    .is_none_or(|arn| !arn.starts_with("arn:"))
                {
                    bail!("HTTPS/TLS listener requires an existing certificate ARN");
                }
            } else if listener.certificate_arn.is_some() || listener.ssl_policy.is_some() {
                bail!("Certificates/SSL policies only apply to HTTPS/TLS listeners");
            }
            if !application
                && !match listener.protocol.as_str() {
                    "TCP" => ["TCP", "TCP_UDP"].contains(&group.protocol.as_str()),
                    "TLS" => ["TCP", "TLS"].contains(&group.protocol.as_str()),
                    "UDP" => group.protocol == "UDP",
                    "TCP_UDP" => group.protocol == "TCP_UDP",
                    _ => false,
                }
            {
                bail!("NLB listener/target group protocols are incompatible");
            }
        }
        Ok(())
    }
}
fn unique(values: &[String], name: &str) -> Result<()> {
    if values.iter().collect::<BTreeSet<_>>().len() != values.len() {
        bail!("{name} must be unique");
    }
    Ok(())
}

pub fn target_schema(instance_keys: Vec<String>, network: bool) -> Node {
    let mut health = Node::scalar(
        "object",
        true,
        "Health check settings; TCP leaves path/matcher unset.",
    );
    for key in ["protocol", "port"] {
        health.properties.insert(
            key.into(),
            Node::scalar(
                "string",
                true,
                "Health protocol HTTP/HTTPS/TCP; port traffic-port or a port number.",
            ),
        );
    }
    for key in ["path", "matcher"] {
        health.properties.insert(
            key.into(),
            Node::scalar("string", false, "HTTP(S) only. Unset for TCP."),
        );
    }
    for key in [
        "interval",
        "timeout",
        "healthy_threshold",
        "unhealthy_threshold",
    ] {
        health.properties.insert(
            key.into(),
            Node::scalar(
                "number",
                true,
                "Health timing in seconds; healthy/unhealthy thresholds 2–10.",
            ),
        );
    }
    let mut group = Node::scalar(
        "object",
        true,
        "Configure protocol, targets, and health checks.",
    );
    group.properties.insert(
        "port".into(),
        Node::scalar("number", true, "Backend application port, 1–65535."),
    );
    for key in ["protocol", "target_type"] {
        group.properties.insert(
            key.into(),
            Node::scalar(
                "string",
                true,
                "ALB HTTP/HTTPS. NLB TCP/TLS/UDP/TCP_UDP. Target type instance or ip.",
            ),
        );
    }
    let mut instance=Node::scalar("string",true,"Select an EC2 key from this environment. Attachment resolves its ID/private IP after creation.");
    instance.choices = instance_keys;
    let mut list = Node::scalar(
        "list",
        false,
        "Project EC2 targets. Add an entry to select an EC2; no manual output IDs needed.",
    );
    list.element = Some(Box::new(instance));
    group.properties.insert("instance_keys".into(), list);
    let mut list = Node::scalar(
        "list",
        false,
        "Existing EC2 IDs or existing IPv4 addresses, matching target_type.",
    );
    list.element = Some(Box::new(Node::scalar(
        "string",
        true,
        "Existing i-... ID or IPv4 address.",
    )));
    group.properties.insert("existing_target_ids".into(), list);
    group.properties.insert("health_check".into(), health);
    group.properties.insert(
        "tags".into(),
        Node::map(
            Node::scalar("string", true, "Resource-specific tag value."),
            "Inherited environment tags apply; these are overrides.",
        ),
    );
    group.properties.get_mut("protocol").unwrap().choices = if network {
        vec!["TCP", "TLS", "UDP", "TCP_UDP"]
    } else {
        vec!["HTTP", "HTTPS"]
    }
    .into_iter()
    .map(str::to_string)
    .collect();
    group.properties.get_mut("target_type").unwrap().choices = vec!["instance".into(), "ip".into()];
    group
        .properties
        .get_mut("health_check")
        .unwrap()
        .properties
        .get_mut("protocol")
        .unwrap()
        .choices = if network {
        vec!["TCP", "HTTP", "HTTPS"]
    } else {
        vec!["HTTP", "HTTPS"]
    }
    .into_iter()
    .map(str::to_string)
    .collect();
    group.default_value = Some(
        serde_json::to_value(
            LoadBalancer::new("sample".into(), network).target_groups["web"].clone(),
        )
        .unwrap(),
    );
    Node::map(group,"Multiple target groups, keyed by stable names. Empty target lists create a group without registered targets.")
}
pub fn listener_schema(network: bool) -> Node {
    let mut node=Node::scalar("object",true,"Each listener forwards to a target group key. HTTPS/TLS requires an existing ACM/IAM certificate.");
    node.properties.insert(
        "port".into(),
        Node::scalar("number", true, "Frontend listening port, 1–65535."),
    );
    for key in ["protocol", "target_group_key"] {
        node.properties.insert(key.into(),Node::scalar("string",true,"Protocol HTTP/HTTPS (ALB), TCP/TLS/UDP/TCP_UDP (NLB), or the target group key to forward to."));
    }
    for key in ["certificate_arn", "ssl_policy"] {
        node.properties.insert(
            key.into(),
            Node::scalar(
                "string",
                false,
                "Optional for secure listeners only. HTTPS/TLS needs a certificate ARN.",
            ),
        );
    }
    node.properties.get_mut("protocol").unwrap().choices = if network {
        vec!["TCP", "TLS", "UDP", "TCP_UDP"]
    } else {
        vec!["HTTP", "HTTPS"]
    }
    .into_iter()
    .map(str::to_string)
    .collect();
    node.default_value = Some(
        serde_json::to_value(
            LoadBalancer::new("sample".into(), network).listeners["frontend"].clone(),
        )
        .unwrap(),
    );
    Node::map(
        node,
        "Multiple frontend listeners with distinct ports; each selects one target group.",
    )
}
