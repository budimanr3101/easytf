use crate::{
    config::Node,
    model::{validate_key, Project, Values},
};
use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::OnceLock;

#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ManagedResource {
    pub kind: String,
    #[serde(default)]
    pub configuration: BTreeMap<String, Value>,
    #[serde(default)]
    pub links: BTreeMap<String, Vec<Reference>>,
    #[serde(default)]
    pub depends_on: Vec<String>,
    #[serde(default)]
    pub tags: BTreeMap<String, String>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Reference {
    pub resource_key: String,
    pub output: String,
}
#[derive(Deserialize)]
pub struct Catalog {
    pub resources: BTreeMap<String, Definition>,
}
#[derive(Deserialize)]
pub struct Definition {
    pub title: String,
    pub schema: Node,
    pub outputs: BTreeMap<String, String>,
}
pub fn catalog() -> &'static Catalog {
    static VALUE: OnceLock<Catalog> = OnceLock::new();
    VALUE.get_or_init(|| {
        serde_json::from_str(include_str!("../schemas/resource-catalog.json"))
            .expect("checked catalog")
    })
}
pub fn validate(values: &Values) -> Result<()> {
    for (key, resource) in &values.managed_resources {
        validate_key(key, "Managed resource key")?;
        let definition = catalog()
            .resources
            .get(&resource.kind)
            .context("Unsupported managed resource type")?;
        let mut configuration = serde_json::to_value(&resource.configuration)?;
        for (pointer, references) in &resource.links {
            let node = node_at(&definition.schema, pointer)?;
            if references.is_empty() {
                bail!("{key}/{pointer}: select at least one reference");
            }
            let array = node.kind == "list";
            let expected = if array {
                node.element
                    .as_deref()
                    .context("Missing list element schema")?
            } else {
                node
            };
            if !array && references.len() != 1 {
                bail!("{key}/{pointer}: this field requires one reference");
            }
            for reference in references {
                let kind = reference_kind(reference, values)?;
                if kind != expected.kind {
                    bail!(
                        "{key}/{pointer}: output type {kind} does not match {}",
                        expected.kind
                    );
                }
            }
            // Type-check the remaining configuration without substituting Terraform expressions into tfvars.
            let placeholder = match expected.kind.as_str() {
                "number" => json!(1),
                "bool" => json!(true),
                "string" => json!("referenced-output"),
                _ => bail!("References support scalar outputs"),
            };
            let replacement = if array {
                let mut items = configuration
                    .pointer(pointer)
                    .and_then(Value::as_array)
                    .cloned()
                    .unwrap_or_default();
                items.extend(references.iter().map(|_| placeholder.clone()));
                Value::Array(items)
            } else {
                placeholder
            };
            set_pointer(&mut configuration, pointer, replacement)?;
        }
        for field in ["policy", "assume_role_policy"] {
            if let Some(text) = configuration.get(field).and_then(Value::as_str) {
                let parsed: Value = serde_json::from_str(text).map_err(|_| {
                    anyhow::anyhow!("{key}/{field}: enter a valid JSON policy object")
                })?;
                if !parsed.is_object() {
                    bail!("{key}/{field}: policy must be a JSON object");
                }
            }
        }
        definition
            .schema
            .validate(&configuration, &format!("{key} ({})", definition.title))?;
        required_collections(&definition.schema, &configuration, key)?;
        for target in &resource.depends_on {
            validate_target(target, values)?;
        }
    }
    let mut visited = BTreeSet::new();
    let mut visiting = BTreeSet::new();
    for key in values.managed_resources.keys() {
        visit(key, values, &mut visiting, &mut visited)?;
    }
    Ok(())
}
fn required_collections(node: &Node, value: &Value, path: &str) -> Result<()> {
    if node.required && value.as_array().is_some_and(Vec::is_empty) {
        bail!("{path}: at least one block/item is required");
    }
    if let Some(object) = value.as_object() {
        for (key, child) in object {
            if let Some(schema) = node.properties.get(key).or(node.element.as_deref()) {
                required_collections(schema, child, &format!("{path}/{key}"))?;
            }
        }
    }
    if let (Some(items), Some(element)) = (value.as_array(), node.element.as_deref()) {
        for (index, child) in items.iter().enumerate() {
            required_collections(element, child, &format!("{path}/{index}"))?;
        }
    }
    Ok(())
}
fn visit(
    key: &str,
    values: &Values,
    visiting: &mut BTreeSet<String>,
    visited: &mut BTreeSet<String>,
) -> Result<()> {
    if visited.contains(key) {
        return Ok(());
    }
    if !visiting.insert(key.into()) {
        bail!("Dependency cycle includes managed resource '{key}'");
    }
    let resource = &values.managed_resources[key];
    for target in resource
        .depends_on
        .iter()
        .chain(resource.links.values().flatten().map(|r| &r.resource_key))
    {
        if values.managed_resources.contains_key(target) {
            visit(target, values, visiting, visited)?;
        }
    }
    visiting.remove(key);
    visited.insert(key.into());
    Ok(())
}
fn validate_target(key: &str, values: &Values) -> Result<()> {
    if let Some(key) = key.strip_prefix("sg:") {
        if values.security_groups.contains_key(key) {
            return Ok(());
        }
    } else if let Some(key) = key.strip_prefix("lb:") {
        if values.load_balancers.contains_key(key) {
            return Ok(());
        }
    } else if let Some(key) = key.strip_prefix("ec2:") {
        if values.instances.contains_key(key) {
            return Ok(());
        }
    } else if values.managed_resources.contains_key(key) {
        return Ok(());
    }
    bail!("Missing dependency '{key}'")
}
fn reference_kind(reference: &Reference, values: &Values) -> Result<String> {
    validate_target(&reference.resource_key, values)?;
    if reference.resource_key.starts_with("sg:") {
        if ["id", "vpc_id"].contains(&reference.output.as_str()) {
            return Ok("string".into());
        }
    } else if reference.resource_key.starts_with("lb:") {
        if ["arn", "dns_name", "zone_id"].contains(&reference.output.as_str()) {
            return Ok("string".into());
        }
    } else if reference.resource_key.starts_with("ec2:") {
        if ["id", "private_ip", "public_ip"].contains(&reference.output.as_str()) {
            return Ok("string".into());
        }
    } else {
        let resource = &values.managed_resources[&reference.resource_key];
        if let Some(kind) = catalog()
            .resources
            .get(&resource.kind)
            .and_then(|d| d.outputs.get(&reference.output))
        {
            return Ok(kind.clone());
        }
    }
    bail!(
        "Unsupported output '{}' for '{}'",
        reference.output,
        reference.resource_key
    )
}
fn node_at<'a>(mut node: &'a Node, pointer: &str) -> Result<&'a Node> {
    if !pointer.starts_with('/') || pointer.len() < 2 {
        bail!("Reference paths use JSON Pointer, e.g. /vpc_id");
    }
    for segment in pointer[1..].split('/') {
        if segment.is_empty()
            || !segment
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_')
        {
            bail!("Invalid reference path segment");
        }
        node = if node.kind == "object" {
            node.properties
                .get(segment)
                .context("Unknown reference field")?
        } else if node.kind == "list" && segment.parse::<usize>().is_ok() {
            node.element.as_deref().context("Missing element schema")?
        } else {
            bail!("Reference paths must select declared fields or existing list blocks");
        };
    }
    Ok(node)
}
fn set_pointer(value: &mut Value, pointer: &str, replacement: Value) -> Result<()> {
    let (parent, field) = pointer.rsplit_once('/').context("Invalid reference path")?;
    let parent = if parent.is_empty() {
        value
    } else {
        value
            .pointer_mut(parent)
            .context("Create the parent block before linking its field")?
    };
    parent
        .as_object_mut()
        .context("Link must select an object attribute")?
        .insert(field.into(), replacement);
    Ok(())
}
fn quote(value: &str) -> String {
    serde_json::to_string(value)
        .unwrap()
        .replace("${", "$${")
        .replace("%{", "%%{")
}
fn module(key: &str) -> String {
    if let Some(key) = key.strip_prefix("sg:") {
        format!("module.security_groups[{}]", quote(key))
    } else if let Some(key) = key.strip_prefix("lb:") {
        format!("module.load_balancers[{}]", quote(key))
    } else if let Some(key) = key.strip_prefix("ec2:") {
        format!("module.instances[{}]", quote(key))
    } else {
        format!("module.managed_{key}")
    }
}
fn reference_expression(reference: &Reference) -> String {
    let base = module(&reference.resource_key);
    if reference.resource_key.starts_with("sg:")
        || reference.resource_key.starts_with("ec2:")
        || reference.resource_key.starts_with("lb:")
    {
        format!("{base}.{}", reference.output)
    } else {
        format!("{base}.fields[{}]", quote(&reference.output))
    }
}
fn configuration_expression(
    value: &Value,
    pointer: &str,
    base: &str,
    links: &BTreeMap<String, Vec<Reference>>,
    schema: &Node,
) -> Result<String> {
    if let Some(references) = links.get(pointer) {
        let expressions = references
            .iter()
            .map(reference_expression)
            .collect::<Vec<_>>();
        return Ok(if node_at(schema, pointer)?.kind == "list" {
            format!(
                "concat(coalesce(try({base}, null), []), [{}])",
                expressions.join(", ")
            )
        } else {
            expressions[0].clone()
        });
    }
    let prefix = format!("{pointer}/");
    if !links.keys().any(|path| path.starts_with(&prefix)) {
        return Ok(base.into());
    }
    match value {
        Value::Object(object) => {
            let mut keys = object.keys().cloned().collect::<BTreeSet<_>>();
            for path in links.keys().filter(|path| path.starts_with(&prefix)) {
                keys.insert(path[prefix.len()..].split('/').next().unwrap().into());
            }
            let mut fields = Vec::new();
            for key in keys {
                let expr = configuration_expression(
                    object.get(&key).unwrap_or(&Value::Null),
                    &format!("{pointer}/{key}"),
                    &format!("try({base}[{}], null)", quote(&key)),
                    links,
                    schema,
                )?;
                fields.push(format!("{} = {expr}", quote(&key)));
            }
            Ok(format!("{{ {} }}", fields.join(", ")))
        }
        Value::Array(items) => Ok(format!(
            "[{}]",
            items
                .iter()
                .enumerate()
                .map(|(index, item)| configuration_expression(
                    item,
                    &format!("{pointer}/{index}"),
                    &format!("{base}[{index}]"),
                    links,
                    schema
                ))
                .collect::<Result<Vec<_>>>()?
                .join(", ")
        )),
        _ => bail!("Create the parent block before linking its field"),
    }
}
pub fn add_files(project: &Project, files: &mut BTreeMap<String, String>) -> Result<()> {
    // Render all catalog modules so loading/removing the last instance preserves the tracked template set.
    for kind in catalog().resources.keys() {
        files.insert(
            format!("modules/catalog/{kind}/main.tf"),
            crate::catalog_templates::template(kind)
                .context("Missing catalog template")?
                .into(),
        );
        files.insert(
            format!("modules/catalog/{kind}/versions.tf"),
            include_str!("../templates/module_versions.tf").into(),
        );
    }
    for (env, environment) in &project.environments {
        let mut root = String::new();
        let mut outputs = Vec::new();
        for (key, resource) in &environment.values.managed_resources {
            let definition = &catalog().resources[&resource.kind];
            let configuration = serde_json::to_value(&resource.configuration)?;
            let expr = configuration_expression(
                &configuration,
                "",
                &format!("var.managed_resources[{}].configuration", quote(key)),
                &resource.links,
                &definition.schema,
            )?;
            root.push_str(&format!("module \"managed_{key}\" {{\n  source = \"../../modules/catalog/{}\"\n  settings = {expr}\n  environment_tags = var.tags\n  resource_tags = try(var.managed_resources[{}].tags, {{}})\n", resource.kind, quote(key)));
            if !resource.depends_on.is_empty() {
                root.push_str(&format!(
                    "  depends_on = [{}]\n",
                    resource
                        .depends_on
                        .iter()
                        .map(|key| module(key))
                        .collect::<Vec<_>>()
                        .join(", ")
                ));
            }
            root.push_str("}\n");
            outputs.push(format!("{} = module.managed_{key}.fields", quote(key)));
        }
        files.insert(format!("environments/{env}/managed-resources.tf"), root);
        files.insert(format!("environments/{env}/managed-resources-variables.tf"), "variable \"managed_resources\" {\n  description = \"Catalog resource inputs and stable dependency references.\"\n  type = any\n  default = {}\n}\n".into());
        files.insert(
            format!("environments/{env}/managed-resources-outputs.tf"),
            format!(
                "output \"managed_resources\" {{\n  value = {{ {} }}\n}}\n",
                outputs.join(", ")
            ),
        );
    }
    for (path, content) in files.iter_mut() {
        if path.ends_with("/managed-resources.tf")
            || path.ends_with("/managed-resources-variables.tf")
            || path.ends_with("/managed-resources-outputs.tf")
        {
            *content = crate::render::format_generated_hcl(content)?;
        }
    }
    Ok(())
}
