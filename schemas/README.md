# Pinned EC2 configuration schema

`aws-instance-6.68.0.json` is the aws_instance resource block exported by Terraform's `providers schema -json` command from the official HashiCorp AWS provider 6.68.0. It contains no account data. `ec2-options.json` is the configurable subset used by the TUI and local validation.

Run `python3 scripts/build-ec2-schema.py` followed by `terraform fmt templates` to rebuild the generated EC2 templates/catalog offline. Base files preserve the shared-module interface and preconditions. The generator excludes computed-only outputs and aliases already managed by basic fields (`ami`, instance type, subnet, security groups, tags, and environment region). It adds EasyTF's optional `instance_role` convenience setting, which creates an instance profile for an existing role.

Provider reference: https://registry.terraform.io/providers/hashicorp/aws/6.68.0/docs/resources/instance
