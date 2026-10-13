# EasyTF

A Rust terminal workspace for generating Terraform projects. All interface text and generated files are in English.

## Try it

```sh
easytf --demo
easytf
# Open a generated project:
easytf --project ./my-project
```

The wizard covers project location, environments, local or existing S3 state storage, EC2, existing subnet/security group IDs, and managed security groups. Review changes before generating. Demo AWS IDs are placeholders: replace them before using Terraform.

## Keyboard

Use arrows and Tab to navigate; Enter opens an item. Ctrl+N continues, `r` reviews, `p` switches preview, Ctrl+S saves a form or working draft, and Esc goes back. In forms, Tab or Enter advances to the visible Save & continue / Save & stay / Cancel actions; use Left/Right to choose an action and Enter to activate it. Ctrl+N saves and continues immediately. F2/F3 remain optional aliases. In Resources, `a` adds EC2, `s` adds a security group, and `d` requests deletion. In Review, `g` generates after confirmation. `?` opens contextual help. On a narrow terminal, `p` opens full-width previews.

## EC2 sections and collection editors

The EC2 form keeps basic identity/network settings together. Press Ctrl+G or open **Optional EC2 configuration** for six sections: Identity & access; Storage; Networking; Metadata/monitoring/protection; Placement/CPU/capacity; Launch/Spot/lifecycle.

These sections cover 44 optional settings derived from the `aws_instance` schema in AWS provider 6.68.0, including its configurable nested blocks. Computed outputs and deprecated aliases for settings already owned by the basic form are excluded. Region comes from the environment. Existing ENIs require an explicit subnet for validation and manage their own SG/IP settings; launch templates can supply the AMI and SGs, while explicit basic values override the template.

- `instance_role` accepts an existing IAM role name and generates an IAM instance profile for it. Alternatively, `iam_instance_profile` uses an existing profile directly; choose one.
- `key_name` uses an existing regional EC2 key pair.
- Storage supports multiple EBS device mappings, disk size/type/encryption/KMS/IOPS/throughput/tags/snapshots, plus root and instance-store options. Do not mix inline EBS mappings with external volume attachment resources on the same instance.
- Optional settings show their purpose. Unset values preserve provider defaults. Legacy root storage remains encrypted gp3 with the basic size unless a root override or launch template supplies storage.

Tags and SG ingress/egress use list editors instead of JSON text. Enter opens a collection or edits one value; it does not save/exit the parent form. Use `a` to add entries, Enter to edit, `d` to remove/unset, and Ctrl+S or the Done action to keep the current page. Esc discards that page. Finally, Ctrl+N saves the parent resource form. Paste multiline user data into its value editor, then Enter or Ctrl+S keeps the value.

Every rule has a stable key such as `https`, `ssh_office`, or `metrics`. Both standalone SGs and **Create new SG** within EC2 support multiple ingress and egress rules. Current rule protocols are TCP, UDP, and all protocols (`-1`) with IPv4 CIDRs.

See `examples/ec2-complete.json` for role, key pair, root disk, multiple EBS disks, IMDSv2, user data, tags, and multiple ingress rules. Provider/API compatibility checks and a Terraform plan are still required before deployment.

Existing 0.1 projects with intact conflict snapshots can be upgraded through the normal review/generate flow. Manual `.tf` edits continue to block overwrites. A clone without snapshots must match the current templates before regeneration; template adoption for manually changed projects remains separate work.

## Browse AWS resources

On an AMI, subnet, or existing SG field, press Ctrl+B. Type to search results, use arrows to select, and Enter to copy the ID into the form. For security groups, Space selects multiple groups; Ctrl+U clears the selection; Enter commits it. Esc cancels without changing the form.

Discovery uses AWS CLI v2 and the active environment's region and optional profile, including its existing SSO/credential configuration. It runs in the background and supports cancellation. No AWS requests happen until you explicitly browse. Subnet and SG discovery requires EC2 describe permissions; groups are filtered to the chosen subnet's primary VPC. AMI browsing currently lists up to 200 Amazon Linux 2023 images, newest first within the returned results, with architecture shown. Custom AMIs remain manual inputs. Discovery does not verify that an instance type matches the chosen AMI architecture.

Scripted discovery is also available:

```sh
easytf discover subnets --region ap-southeast-1 --profile my-profile
easytf discover security-groups --region ap-southeast-1 --profile my-profile --subnet subnet-0123456789abcdef0
easytf discover images --region ap-southeast-1 --profile my-profile
```

## Project layout

Shared modules live in `modules/`; each environment has its own root under `environments/<name>/`, including `terraform.tfvars` and backend configuration. Existing AWS resources use data sources. Managed dependencies use module outputs and stable map keys. Editing an instance Name does not change its Terraform address.

Edit supported values directly in `terraform.tfvars`, then reopen the project. EasyTF preserves unrelated files and blocks overwriting manually edited generated Terraform. Drafts contain committed forms; unfinished form edits are discarded when leaving the form. After interrupted publication, use `easytf recover --project <path>`.

## Scripted generation

```sh
easytf example > config.json
easytf generate --config config.json --output ./example --dry-run
easytf generate --config config.json --output ./example
easytf check --project ./example
cd example/environments/dev
terraform init
terraform validate
terraform plan
```

For S3, use `terraform init -backend-config=backend.s3.tfbackend`. Backend values stay separate from resource tfvars. State buckets must already exist.

## Scope

This MVP generates files and output definitions; it never applies infrastructure. Explicit discovery makes read-only AWS requests; manual generation works offline. Importing unmanaged Terraform projects, automatic state/backend migrations, and fetching applied output values are future work. EC2 security groups must belong to the subnet's primary VPC; extra security group VPC associations are outside this MVP. Inputs and draft files may contain sensitive values; do not store AWS credentials in them.

## Build and verify

Rust 1.88 or newer is required.

```sh
cargo build --release
cargo test
cargo clippy --all-targets -- -D warnings
python3 tests/tui_smoke.py
python3 tests/tui_collections_smoke.py
```

Terraform requires version 1.10 or newer, below 2.0. The generated AWS provider requirement is `>= 6.68.0, < 7.0`.
