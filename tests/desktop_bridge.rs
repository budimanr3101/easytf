use serde_json::{json, Value};
use std::{
    io::Write,
    process::{Command, Stdio},
};
fn call(request: Value) -> Value {
    let mut process = Command::new(env!("CARGO_BIN_EXE_easytf-desktop"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    process
        .stdin
        .take()
        .unwrap()
        .write_all(serde_json::to_string(&request).unwrap().as_bytes())
        .unwrap();
    let output = process.wait_with_output().unwrap();
    assert!(output.status.success());
    serde_json::from_slice(&output.stdout).unwrap()
}
#[test]
fn native_roundtrip_preserves_complete_ec2_and_load_balancers() {
    let folder = tempfile::tempdir().unwrap();
    let root = folder.path().join("infra");
    let project: Value =
        serde_json::from_str(include_str!("../examples/ec2-alb-nlb.json")).unwrap();
    let preview = call(json!({"operation":"preview", "root":root,"project":project}));
    assert_eq!(preview["ok"], true, "{preview}");
    assert!(!root.exists(), "preview must not write the project");
    assert!(preview["data"]["files"]["environments/dev/terraform.tfvars"].is_string());
    let published = call(json!({"operation":"publish", "root":root,"project":project}));
    assert_eq!(published["ok"], true, "{published}");
    let opened = call(json!({"operation":"open", "root":root}));
    assert_eq!(opened["ok"], true);
    assert_eq!(
        opened["data"]["project"]["environments"]["dev"]["values"]["load_balancers"],
        project["environments"]["dev"]["values"]["load_balancers"]
    );
    let republished = call(
        json!({"operation":"publish","root":root,"project":opened["data"]["project"],"baseline":opened["data"]["baseline"]}),
    );
    assert_eq!(republished["ok"], true, "{republished}");
}
#[test]
fn native_bridge_rejects_stale_inputs_without_writes() {
    let folder = tempfile::tempdir().unwrap();
    let root = folder.path().join("infra");
    let project: Value =
        serde_json::from_str(include_str!("../examples/ec2-existing.json")).unwrap();
    assert_eq!(
        call(json!({"operation":"publish", "root":root,"project":project}))["ok"],
        true
    );
    let opened = call(json!({"operation":"open", "root":root}));
    let file = root.join("environments/dev/terraform.tfvars");
    let mut external = std::fs::read_to_string(&file).unwrap();
    external.push_str("\n# Edited outside native app\n");
    std::fs::write(&file, &external).unwrap();
    let result = call(
        json!({"operation":"publish","root":root,"project":opened["data"]["project"],"baseline":opened["data"]["baseline"]}),
    );
    assert_eq!(result["ok"], false);
    assert!(result["error"]
        .as_str()
        .unwrap()
        .contains("changed outside"));
    assert_eq!(std::fs::read_to_string(&file).unwrap(), external);
}
