use easytf::{catalog, model::Project, project, render};
use serde_json::json;
fn fixture() -> Project {
    serde_json::from_str(include_str!("../examples/catalog-complete.json")).unwrap()
}
#[test]
fn all_catalog_types_roundtrip_and_keep_inputs_in_tfvars() {
    let model = fixture();
    model.validate().unwrap();
    assert_eq!(catalog::catalog().resources.len(), 43);
    let kinds = model.environments["dev"]
        .values
        .managed_resources
        .values()
        .map(|r| r.kind.as_str())
        .collect::<std::collections::BTreeSet<_>>();
    assert_eq!(kinds.len(), 43);
    let root = tempfile::tempdir().unwrap();
    let published = project::publish(root.path(), &model, None).unwrap();
    let loaded = project::load(root.path()).unwrap();
    assert_eq!(loaded.project, model);
    project::publish(root.path(), &model, Some(&published)).unwrap();
    let files = render::render(&model).unwrap();
    let main = &files["environments/dev/managed-resources.tf"];
    assert!(main.contains("module.managed_subnet.fields[\"id\"]"));
    assert!(main.contains("module.managed_iam_role_policy_attachment"));
    assert!(!main.contains("10.60.0.0/16"));
    assert!(files["environments/dev/terraform.tfvars"].contains("10.60.0.0/16"));
    assert!(
        files["modules/catalog/aws_db_instance/main.tf"].contains("manage_master_user_password")
    );
    assert!(!files["modules/catalog/aws_db_instance/main.tf"].contains("password_wo_version"));
}
#[test]
fn graph_cycles_dangling_outputs_wrong_types_and_missing_blocks_are_rejected() {
    let mut model = fixture();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .managed_resources
        .get_mut("vpc")
        .unwrap()
        .depends_on
        .push("subnet".into());
    assert!(model.validate().unwrap_err().to_string().contains("cycle"));
    let mut model = fixture();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .managed_resources
        .get_mut("subnet")
        .unwrap()
        .links
        .get_mut("/vpc_id")
        .unwrap()[0]
        .output = "missing".into();
    assert!(model.validate().is_err());
    let mut model = fixture();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .managed_resources
        .get_mut("eks_cluster")
        .unwrap()
        .configuration
        .insert("vpc_config".into(), json!([]));
    assert!(model.validate().is_err());
    let mut model = fixture();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .managed_resources
        .get_mut("subnet")
        .unwrap()
        .links
        .get_mut("/vpc_id")
        .unwrap()[0]
        .resource_key = "missing".into();
    assert!(model.validate().is_err());
    let mut model = fixture();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .managed_resources
        .get_mut("iam_role")
        .unwrap()
        .configuration
        .insert("assume_role_policy".into(), json!("not-json"));
    assert!(model.validate().is_err());
}
