#![cfg(unix)]
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

#[test]
fn discovery_passes_profile_region_and_subnet_vpc_filter_without_writes() {
    let temp = tempfile::tempdir().unwrap();
    let aws = temp.path().join("aws");
    fs::write(&aws, r#"#!/bin/sh
printf '%s\n' "$@" >> "$EASYTF_TEST_ARGUMENT_LOG"
if [ "$EASYTF_TEST_FAILURE" = "1" ]; then
  echo 'ExpiredToken: refresh the session' >&2
  exit 1
fi
case "$*" in
  *describe-security-groups*) printf '%s\n' '{"SecurityGroups":[{"GroupId":"sg-11111111","GroupName":"application","VpcId":"vpc-12345678"}]}' ;;
  *describe-images*) printf '%s\n' '{"Images":[{"ImageId":"ami-11111111","Name":"al2023-test","Architecture":"arm64","CreationDate":"2026-10-01"}]}' ;;
  *describe-subnets*) printf '%s\n' '{"Subnets":[{"SubnetId":"subnet-11111111","VpcId":"vpc-12345678","AvailabilityZone":"ap-southeast-1a","CidrBlock":"10.0.0.0/24"}]}' ;;
  *) exit 2 ;;
esac
"#).unwrap();
    fs::set_permissions(&aws, fs::Permissions::from_mode(0o755)).unwrap();
    let log = temp.path().join("args");
    let path = format!(
        "{}:{}",
        temp.path().display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let mut cmd = Command::new(env!("CARGO_BIN_EXE_easytf"));
    cmd.env("PATH", &path)
        .env("EASYTF_TEST_ARGUMENT_LOG", &log)
        .args([
            "discover",
            "security-groups",
            "--region",
            "ap-southeast-1",
            "--profile",
            "test-profile",
            "--subnet",
            "subnet-11111111",
        ]);
    let output = cmd.output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let items: serde_json::Value = serde_json::from_slice(&output.stdout).unwrap();
    assert_eq!(items[0]["id"], "sg-11111111");
    let args = fs::read_to_string(&log).unwrap();
    assert!(args.contains("--profile\ntest-profile"));
    assert!(args.contains("--region\nap-southeast-1"));
    assert!(args.contains("describe-subnets"));
    assert!(args.contains("Name=vpc-id,Values=vpc-12345678"));
    assert!(!args.contains("create-"));
    cmd.env("EASYTF_TEST_FAILURE", "1");
    let failure = cmd.output().unwrap();
    assert!(!failure.status.success());
    assert!(String::from_utf8_lossy(&failure.stderr).contains("ExpiredToken"));
}
