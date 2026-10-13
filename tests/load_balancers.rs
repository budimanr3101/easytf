use easytf::{lb::LoadBalancer, model::Project, project, render};

#[test]
fn alb_nlb_dependencies_and_environment_tags_roundtrip() {
    let model: Project =
        serde_json::from_str(include_str!("../examples/ec2-alb-nlb.json")).unwrap();
    let files = render::render(&model).unwrap();
    let main = &files["environments/dev/main.tf"];
    assert!(
        main.contains("id         = module.instances[key].id")
            || main.contains("id = module.instances[key].id")
    );
    assert!(main.contains("tags        = merge(var.tags, each.value.tags)"));
    let lb = &files["modules/load-balancer/main.tf"];
    assert!(lb.contains("jsonencode([group_key, \"project\", instance_key])"));
    assert!(!lb.contains("depends_on"));
    assert!(lb.contains("aws_lb_target_group_attachment"));
    let directory = tempfile::tempdir().unwrap();
    project::publish(directory.path(), &model, None).unwrap();
    assert_eq!(project::load(directory.path()).unwrap().project, model);
}

#[test]
fn invalid_links_secure_listeners_and_wrong_protocols_are_rejected() {
    let mut model: Project =
        serde_json::from_str(include_str!("../examples/ec2-alb-nlb.json")).unwrap();
    let env = model.environments.get_mut("dev").unwrap();
    let mut alb = env.values.load_balancers["frontend_alb"].clone();
    alb.target_groups.get_mut("web").unwrap().instance_keys = vec!["missing".into()];
    assert!(alb
        .validate(&env.values)
        .unwrap_err()
        .to_string()
        .contains("missing EC2"));
    alb = env.values.load_balancers["frontend_alb"].clone();
    alb.listeners.get_mut("frontend").unwrap().protocol = "HTTPS".into();
    assert!(alb
        .validate(&env.values)
        .unwrap_err()
        .to_string()
        .contains("certificate"));
    let mut nlb = LoadBalancer::new("app-nlb".into(), true);
    nlb.subnet_ids = vec!["subnet-12345678".into()];
    assert!(nlb.validate(&env.values).is_ok());
    nlb.target_groups.get_mut("web").unwrap().protocol = "HTTP".into();
    assert!(nlb.validate(&env.values).is_err());
}

#[test]
fn defaults_are_environment_scoped_not_copied_to_resources() {
    let model = Project::empty("test-project");
    assert_eq!(model.environments["dev"].values.tags["env"], "dev");
    assert_eq!(
        model.environments["dev"].values.tags["project"],
        "test-project"
    );
    assert!(model.environments["dev"].values.instances.is_empty());
}
