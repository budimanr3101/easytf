use easytf::{config, model::Project, project, render};
use std::{collections::BTreeSet, fs};

#[test]
fn all_optional_arguments_have_a_ui_section_and_survive_tfvars_roundtrip() {
    let schema = config::ec2_schema();
    let covered: BTreeSet<_> = config::GROUPS
        .iter()
        .flat_map(|(_, _, keys)| keys.iter().map(|key| key.to_string()))
        .collect();
    assert_eq!(covered, schema.properties.keys().cloned().collect());
    let model: Project =
        serde_json::from_str(include_str!("../examples/ec2-complete.json")).unwrap();
    let files = render::render(&model).unwrap();
    let restored: easytf::model::Values =
        hcl::from_str(&files["environments/dev/terraform.tfvars"]).unwrap();
    assert_eq!(restored, model.environments["dev"].values);
    assert_eq!(
        restored.instances["web_primary"].configuration["ebs_block_device"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    assert_eq!(restored.security_groups["application"].ingress.len(), 3);
    assert!(files["modules/ec2/main.tf"].contains("resource \"aws_iam_instance_profile\" \"role\""));
    assert!(files["modules/ec2/main.tf"].contains("dynamic \"ebs_block_device\""));
    assert!(files["modules/ec2/main.tf"].contains("dynamic \"metadata_options\""));
    let temp = tempfile::tempdir().unwrap();
    project::publish(temp.path(), &model, None).unwrap();
    assert_eq!(project::load(temp.path()).unwrap().project, model);
}

#[test]
fn conflicting_identity_unknown_options_and_invalid_disks_are_rejected() {
    let mut model = Project::demo();
    let instance = model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap();
    instance
        .configuration
        .insert("instance_role".into(), "ApplicationRole".into());
    instance
        .configuration
        .insert("iam_instance_profile".into(), "ExistingProfile".into());
    assert!(model
        .validate()
        .unwrap_err()
        .to_string()
        .contains("cannot be configured together"));
    let instance = model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap();
    instance.configuration.clear();
    instance.configuration.insert("ebs_block_device".into(), serde_json::json!([{"device_name":"/dev/sdf","volume_size":20},{"device_name":"/dev/sdf","volume_size":40}]));
    assert!(model
        .validate()
        .unwrap_err()
        .to_string()
        .contains("unique device_name"));
    let instance = model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap();
    instance.configuration.clear();
    instance
        .configuration
        .insert("unsupported".into(), true.into());
    assert!(model
        .validate()
        .unwrap_err()
        .to_string()
        .contains("unknown configuration"));
}

#[test]
fn old_template_metadata_can_upgrade_without_losing_resource_identity() {
    let temp = tempfile::tempdir().unwrap();
    let model = Project::demo();
    project::publish(temp.path(), &model, None).unwrap();
    let metadata = temp.path().join(".easytf.toml");
    let old = fs::read_to_string(&metadata)
        .unwrap()
        .replace(easytf::model::TEMPLATE_VERSION, "0.1.0");
    fs::write(&metadata, &old).unwrap();
    let snapshot_path = temp.path().join(".easytf/last-generated.json");
    let mut snapshot: serde_json::Value =
        serde_json::from_slice(&fs::read(&snapshot_path).unwrap()).unwrap();
    snapshot["hashes"][".easytf.toml"] = project::hash(old.as_bytes()).into();
    fs::write(snapshot_path, snapshot.to_string()).unwrap();
    let loaded = project::load(temp.path()).unwrap();
    assert_eq!(loaded.project, model);
    project::publish(temp.path(), &loaded.project, Some(&loaded)).unwrap();
    assert!(fs::read_to_string(metadata)
        .unwrap()
        .contains(easytf::model::TEMPLATE_VERSION));
    assert!(
        project::load(temp.path()).unwrap().project.environments["dev"]
            .values
            .instances
            .contains_key("web_primary")
    );
}
