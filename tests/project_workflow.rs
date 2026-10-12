use easytf::{
    model::{Backend, Project, Rule, SecurityGroup},
    project, render,
};
use std::collections::BTreeMap;
use std::fs;

#[test]
fn mixed_dependencies_generate_data_modules_and_outputs() {
    let mut model = Project::demo();
    let env = model.environments.get_mut("dev").unwrap();
    env.values.security_groups.insert(
        "shared".into(),
        SecurityGroup {
            name: "application-dev".into(),
            description: "Shared application group".into(),
            subnet_id: "subnet-0123456789abcdef0".into(),
            ingress: BTreeMap::from([(
                "https".into(),
                Rule {
                    protocol: "tcp".into(),
                    from_port: Some(443),
                    to_port: Some(443),
                    cidr_ipv4: "10.0.0.0/16".into(),
                    description: "Application access".into(),
                },
            )]),
            egress: easytf::model::default_egress(),
            tags: BTreeMap::new(),
        },
    );
    env.values
        .instances
        .get_mut("web_primary")
        .unwrap()
        .security_group_keys
        .push("shared".into());
    let files = render::render(&model).unwrap();
    let main = &files["environments/dev/main.tf"];
    assert!(main.contains("data \"aws_subnet\" \"existing\""));
    assert!(main.contains("data \"aws_security_group\" \"existing\""));
    assert!(main.contains("module.security_groups[key].id"));
    assert!(files["environments/dev/outputs.tf"].contains("existing_subnets"));
    let restored: easytf::model::Values =
        hcl::from_str(&files["environments/dev/terraform.tfvars"]).unwrap();
    assert_eq!(restored, model.environments["dev"].values);
    for (path, text) in files {
        if path.ends_with(".tf") || path.ends_with(".tfvars") {
            hcl::parse(&text).unwrap();
        }
    }
}

#[test]
fn generate_again_is_idempotent_and_loads_manual_tfvars_changes() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("project");
    let model = Project::demo();
    let loaded = project::publish(&root, &model, None).unwrap();
    assert!(project::changes(&root, &model)
        .unwrap()
        .iter()
        .all(|c| c.action == "unchanged"));
    project::publish(&root, &model, Some(&loaded)).unwrap();
    let path = root.join("environments/dev/terraform.tfvars");
    let text = fs::read_to_string(&path)
        .unwrap()
        .replace("t3.micro", "t3.large");
    fs::write(&path, text).unwrap();
    let loaded = project::load(&root).unwrap();
    assert_eq!(
        loaded.project.environments["dev"].values.instances["web_primary"].instance_type,
        "t3.large"
    );
    let mut updated = loaded.project.clone();
    let mut instance = updated.environments["dev"].values.instances["web_primary"].clone();
    instance.name = "worker-dev".into();
    updated
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .insert("worker".into(), instance);
    project::publish(&root, &updated, Some(&loaded)).unwrap();
    let loaded = project::load(&root).unwrap();
    assert_eq!(
        loaded.project.environments["dev"].values.instances["web_primary"].instance_type,
        "t3.large"
    );
    assert_eq!(loaded.project.environments["dev"].values.instances.len(), 2);
}

#[test]
fn manual_generated_edits_and_stale_inputs_block_all_writes() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("project");
    let model = Project::demo();
    project::publish(&root, &model, None).unwrap();
    let path = root.join("modules/ec2/main.tf");
    let changed = format!(
        "{}\n# Manual extension\n",
        fs::read_to_string(&path).unwrap()
    );
    fs::write(&path, &changed).unwrap();
    let loaded = project::load(&root).unwrap();
    let before = fs::read(root.join("environments/dev/terraform.tfvars")).unwrap();
    let mut updated = loaded.project.clone();
    updated
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap()
        .instance_type = "t3.large".into();
    assert!(project::publish(&root, &updated, Some(&loaded))
        .unwrap_err()
        .to_string()
        .contains("manual edits"));
    assert_eq!(fs::read_to_string(path).unwrap(), changed);
    assert_eq!(
        fs::read(root.join("environments/dev/terraform.tfvars")).unwrap(),
        before
    );

    let root = directory.path().join("second-project");
    let loaded = project::publish(&root, &model, None).unwrap();
    fs::write(
        root.join("environments/dev/terraform.tfvars"),
        "# Changed concurrently\n",
    )
    .unwrap();
    assert!(project::publish(&root, &model, Some(&loaded))
        .unwrap_err()
        .to_string()
        .contains("changed after"));
}

#[test]
fn state_collisions_missing_links_and_unsafe_paths_are_rejected() {
    let mut model = Project::demo();
    for env in model.environments.values_mut() {
        env.backend = Backend::S3 {
            bucket: "existing-company-state".into(),
            key: "same.tfstate".into(),
            region: "ap-southeast-1".into(),
            use_lockfile: true,
        };
    }
    assert!(model
        .validate()
        .unwrap_err()
        .to_string()
        .contains("duplicate S3 state"));
    let mut model = Project::demo();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap()
        .security_group_keys
        .push("missing".into());
    assert!(model
        .validate()
        .unwrap_err()
        .to_string()
        .contains("does not exist"));
    model.name = "../../escape".into();
    assert!(model.validate().is_err());
}

#[test]
fn s3_config_and_backend_migrations_remain_separate_from_tfvars() {
    let mut model = Project::demo();
    for (name, env) in &mut model.environments {
        env.backend = Backend::S3 {
            bucket: "existing-company-state".into(),
            key: format!("payment/{name}/terraform.tfstate"),
            region: "ap-southeast-1".into(),
            use_lockfile: true,
        };
    }
    let files = render::render(&model).unwrap();
    assert!(files["environments/dev/backend.s3.tfbackend"].contains("use_lockfile = true"));
    assert!(!files["environments/dev/terraform.tfvars"].contains("existing-company-state"));
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("project");
    let loaded = project::publish(&root, &model, None).unwrap();
    model.environments.get_mut("dev").unwrap().backend = Backend::Local;
    assert!(project::publish(&root, &model, Some(&loaded))
        .unwrap_err()
        .to_string()
        .contains("Backend changes"));
}

#[test]
fn user_strings_are_literals_and_unsupported_tfvars_are_not_silently_dropped() {
    let mut model = Project::demo();
    model
        .environments
        .get_mut("dev")
        .unwrap()
        .values
        .instances
        .get_mut("web_primary")
        .unwrap()
        .name = "${file(\"secret\")}\nquoted \"name\"".into();
    let files = render::render(&model).unwrap();
    assert!(files["environments/dev/terraform.tfvars"].contains("$${file"));
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("project");
    project::publish(&root, &model, None).unwrap();
    let path = root.join("environments/dev/terraform.tfvars");
    let text = fs::read_to_string(&path).unwrap() + "\ncustom_setting = true\n";
    fs::write(&path, &text).unwrap();
    assert!(project::load(&root).is_err());
    assert_eq!(fs::read_to_string(path).unwrap(), text);
}

#[cfg(unix)]
#[test]
fn publishing_refuses_symbolic_links_into_other_directories() {
    let directory = tempfile::tempdir().unwrap();
    let root = directory.path().join("project");
    let model = Project::demo();
    let loaded = project::publish(&root, &model, None).unwrap();
    let target = directory.path().join("unrelated.txt");
    fs::write(&target, "Preserve unrelated contents").unwrap();
    let path = root.join("environments/dev/main.tf");
    fs::remove_file(&path).unwrap();
    std::os::unix::fs::symlink(&target, path).unwrap();
    assert!(project::publish(&root, &model, Some(&loaded)).is_err());
    assert_eq!(
        fs::read_to_string(target).unwrap(),
        "Preserve unrelated contents"
    );
}

#[cfg(unix)]
#[test]
fn recovery_restores_partial_publish_and_preserves_independent_edits() {
    use sha2::{Digest, Sha256};
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path();
    std::fs::create_dir(root.join(".easytf")).unwrap();
    let after = b"partial publication";
    let digest = format!("{:x}", Sha256::digest(after));
    let journal = serde_json::json!({"pid": 2147483647u32,
        "originals": {"README.md": b"original".to_vec()},
        "after_hashes": {"README.md": digest}, "stage": ".easytf-stage-test"});
    std::fs::write(root.join(".easytf/transaction.json"), journal.to_string()).unwrap();
    std::fs::write(root.join("README.md"), "independent edit").unwrap();
    assert!(project::recover(root).is_err());
    assert_eq!(
        std::fs::read_to_string(root.join("README.md")).unwrap(),
        "independent edit"
    );
    std::fs::write(root.join("README.md"), after).unwrap();
    assert_eq!(project::recover(root).unwrap(), 1);
    assert_eq!(
        std::fs::read_to_string(root.join("README.md")).unwrap(),
        "original"
    );
    std::fs::write(root.join(".easytf.lock"), std::process::id().to_string()).unwrap();
    assert!(project::recover(root)
        .unwrap_err()
        .to_string()
        .contains("still running"));
}

#[test]
fn resuming_a_draft_refuses_changes_made_after_it_was_saved() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("project");
    let model = Project::demo();
    let loaded = project::publish(&root, &model, None).unwrap();
    let draft = temp.path().join("draft.json");
    project::save_draft(&draft, &model, &root, Some(&loaded)).unwrap();
    assert!(project::load_draft(&draft).is_ok());
    let input = root.join("environments/dev/terraform.tfvars");
    let text = fs::read_to_string(&input)
        .unwrap()
        .replace("t3.micro", "t3.large");
    fs::write(input, text).unwrap();
    assert!(project::load_draft(&draft)
        .unwrap_err()
        .to_string()
        .contains("changed since"));
}
