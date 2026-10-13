use anyhow::{bail, Result};
use serde::Deserialize;
use serde_json::{Map, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Deserialize)]
pub struct Node {
    pub kind: String,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub help: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub choices: Vec<String>,
    #[serde(default)]
    pub default_value: Option<Value>,
    #[serde(default)]
    pub properties: BTreeMap<String, Node>,
    #[serde(default)]
    pub element: Option<Box<Node>>,
    pub max_items: Option<usize>,
}

impl Node {
    pub fn scalar(kind: &str, required: bool, help: &str) -> Self {
        Self {
            kind: kind.into(),
            required,
            help: help.into(),
            label: String::new(),
            choices: Vec::new(),
            default_value: None,
            properties: BTreeMap::new(),
            element: None,
            max_items: None,
        }
    }
    pub fn map(element: Self, help: &str) -> Self {
        Self {
            element: Some(Box::new(element)),
            ..Self::scalar("map", false, help)
        }
    }
    pub fn empty(&self) -> Value {
        if let Some(value) = &self.default_value {
            return value.clone();
        }
        match self.kind.as_str() {
            "object"
                if self.properties.contains_key("protocol")
                    && self.properties.contains_key("cidr_ipv4") =>
            {
                serde_json::json!({"protocol":"tcp","from_port":443,"to_port":443,"cidr_ipv4":"10.0.0.0/16","description":""})
            }
            "object"
                if self.properties.contains_key("device_name")
                    && self.properties.contains_key("volume_size") =>
            {
                serde_json::json!({"device_name":"","volume_size":20,"volume_type":"gp3","encrypted":true,"delete_on_termination":true})
            }
            "object" if self.properties.contains_key("volume_size") => {
                serde_json::json!({"volume_size":20,"volume_type":"gp3","encrypted":true,"delete_on_termination":true})
            }
            "object" | "map" => Value::Object(Map::new()),
            "list" => Value::Array(vec![]),
            "string" if self.required => Value::String(String::new()),
            _ => Value::Null,
        }
    }
    pub fn validate(&self, value: &Value, path: &str) -> Result<()> {
        if value.is_null() {
            if self.required {
                bail!("{path}: a value is required");
            }
            return Ok(());
        }
        match self.kind.as_str() {
            "string" | "choice" if value.is_string() => {
                if !self.choices.is_empty()
                    && !self
                        .choices
                        .iter()
                        .any(|choice| Some(choice.as_str()) == value.as_str())
                {
                    bail!("{path}: choose one of {}", self.choices.join(", "));
                }
            }
            "number" if value.is_number() => {}
            "bool" if value.is_boolean() => {}
            "object" => {
                let Some(values) = value.as_object() else {
                    bail!("{path}: expected an object");
                };
                for (key, val) in values {
                    let node = self
                        .properties
                        .get(key)
                        .ok_or_else(|| anyhow::anyhow!("{path}: unknown configuration '{key}'"))?;
                    node.validate(val, &format!("{path}.{key}"))?;
                }
                if self.properties.contains_key("device_name")
                    && self.properties.contains_key("volume_size")
                    && value["device_name"]
                        .as_str()
                        .is_none_or(|v| v.trim().is_empty())
                {
                    bail!("{path}.device_name: a nonempty device name is required");
                }
                if self.properties.contains_key("protocol")
                    && self.properties.contains_key("cidr_ipv4")
                {
                    serde_json::from_value::<crate::model::Rule>(value.clone())?.validate()?;
                }
                for (key, node) in &self.properties {
                    if node.required && !values.contains_key(key) {
                        bail!("{path}.{key}: required when this section is enabled");
                    }
                }
            }
            "map" => {
                let Some(values) = value.as_object() else {
                    bail!("{path}: expected a map");
                };
                for (key, val) in values {
                    if self
                        .element
                        .as_ref()
                        .unwrap()
                        .properties
                        .contains_key("protocol")
                    {
                        crate::model::validate_key(key, "Rule key")?;
                    }
                    self.element
                        .as_ref()
                        .unwrap()
                        .validate(val, &format!("{path}.{key}"))?;
                }
            }
            "list" => {
                let Some(values) = value.as_array() else {
                    bail!("{path}: expected a list");
                };
                if self.max_items.is_some_and(|max| values.len() > max) {
                    bail!(
                        "{path}: this section accepts at most {} entry",
                        self.max_items.unwrap()
                    );
                }
                for (i, val) in values.iter().enumerate() {
                    self.element
                        .as_ref()
                        .unwrap()
                        .validate(val, &format!("{path}[{i}]"))?;
                }
            }
            _ => bail!("{path}: expected {}", self.kind),
        }
        Ok(())
    }
}

pub fn ec2_schema() -> Node {
    serde_json::from_str(include_str!("../schemas/ec2-options.json"))
        .expect("checked-in EC2 schema")
}

pub const GROUPS: &[(&str, &str, &[&str])] = &[
    (
        "access",
        "Identity & access (optional)",
        &[
            "instance_role",
            "iam_instance_profile",
            "key_name",
            "user_data",
            "user_data_base64",
            "user_data_replace_on_change",
            "get_password_data",
        ],
    ),
    (
        "storage",
        "Storage & additional EBS (optional)",
        &[
            "root_block_device",
            "ebs_block_device",
            "ephemeral_block_device",
            "ebs_optimized",
            "volume_tags",
        ],
    ),
    (
        "network",
        "Advanced networking (optional)",
        &[
            "private_ip",
            "secondary_private_ips",
            "ipv6_address_count",
            "ipv6_addresses",
            "enable_primary_ipv6",
            "source_dest_check",
            "primary_network_interface",
            "network_interface",
            "secondary_network_interface",
            "private_dns_name_options",
        ],
    ),
    (
        "security",
        "Metadata, monitoring & protection (optional)",
        &[
            "metadata_options",
            "enclave_options",
            "monitoring",
            "disable_api_stop",
            "disable_api_termination",
            "force_destroy",
        ],
    ),
    (
        "placement",
        "Placement, CPU & capacity (optional)",
        &[
            "availability_zone",
            "tenancy",
            "host_id",
            "host_resource_group_arn",
            "placement_group",
            "placement_group_id",
            "placement_partition_number",
            "cpu_options",
            "credit_specification",
            "capacity_reservation_specification",
        ],
    ),
    (
        "launch",
        "Launch template, Spot & lifecycle (optional)",
        &[
            "launch_template",
            "instance_market_options",
            "hibernation",
            "instance_initiated_shutdown_behavior",
            "maintenance_options",
            "timeouts",
        ],
    ),
];

pub fn group_schema(keys: &[&str]) -> Node {
    let mut schema = ec2_schema();
    schema
        .properties
        .retain(|key, _| keys.contains(&key.as_str()));
    schema
}

pub fn rules_schema() -> Node {
    let mut node = Node::scalar("object", true, "Each rule has a stable key. Add as many rules as needed. TCP/UDP require ports; -1 means all protocols and no ports.");
    node.properties = BTreeMap::from([
        (
            "protocol".into(),
            Node::scalar("string", true, "tcp, udp, or -1 (all protocols)"),
        ),
        (
            "from_port".into(),
            Node::scalar(
                "number",
                false,
                "TCP/UDP starting port, 0–65535. Unset for all protocols.",
            ),
        ),
        (
            "to_port".into(),
            Node::scalar(
                "number",
                false,
                "TCP/UDP ending port, 0–65535. Unset for all protocols.",
            ),
        ),
        (
            "cidr_ipv4".into(),
            Node::scalar("string", true, "IPv4 network CIDR, such as 10.0.0.0/16."),
        ),
        (
            "description".into(),
            Node::scalar("string", true, "Rule description."),
        ),
    ]);
    Node::map(
        node,
        "Named rules; Enter opens the list. Add, edit, or delete individual rules.",
    )
}

pub fn validate_ec2(values: &BTreeMap<String, Value>) -> Result<()> {
    ec2_schema().validate(&serde_json::to_value(values)?, "EC2")?;
    let set = |key: &str| {
        values.get(key).is_some_and(|v| match v {
            Value::Null => false,
            Value::Array(v) => !v.is_empty(),
            Value::String(v) => !v.is_empty(),
            _ => true,
        })
    };
    for (a, b) in [
        ("instance_role", "iam_instance_profile"),
        ("user_data", "user_data_base64"),
        ("ipv6_addresses", "ipv6_address_count"),
        ("host_id", "host_resource_group_arn"),
        ("placement_group", "placement_group_id"),
        ("primary_network_interface", "network_interface"),
    ] {
        if set(a) && set(b) {
            bail!("EC2: {a} and {b} cannot be configured together");
        }
    }
    if let Some(role) = values.get("instance_role").and_then(Value::as_str) {
        if role.is_empty()
            || role.len() > 64
            || !role
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || "+=,.@_-".contains(c))
        {
            bail!("instance_role must be an IAM role name, not an ARN");
        }
    }
    let mut devices = std::collections::BTreeSet::new();
    for disk in values
        .get("ebs_block_device")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let device = disk["device_name"].as_str().unwrap_or("");
        if device.is_empty() || !devices.insert(device) {
            bail!("Each EBS disk needs a unique device_name");
        }
        if disk["volume_size"].is_null() && disk["snapshot_id"].is_null() {
            bail!("EBS {device}: choose volume_size or snapshot_id");
        }
    }
    for kind in ["ebs_block_device", "root_block_device"] {
        for disk in values
            .get(kind)
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            if disk["volume_size"]
                .as_f64()
                .is_some_and(|n| n <= 0.0 || n.fract() != 0.0)
            {
                bail!("{kind}: volume_size must be a positive integer");
            }
            if !disk["kms_key_id"].is_null() && disk["encrypted"] == false {
                bail!("{kind}: KMS key requires encryption");
            }
        }
    }
    Ok(())
}
