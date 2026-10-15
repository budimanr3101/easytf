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

Use arrows and Tab to navigate; Enter opens an item. Ctrl+N continues, `r` reviews, `p` switches preview, Ctrl+S saves a form or working draft, and Esc goes back. In forms, Tab or Enter advances to the visible Save & continue / Save & stay / Cancel actions; use Left/Right to choose an action and Enter to activate it. Ctrl+N saves and continues immediately. F2/F3 remain optional aliases. In Resources, `a` adds EC2, `s` adds a security group, `l` adds ALB, `b` adds NLB, and `d` requests deletion. In Review, `g` generates after confirmation. `?` opens contextual help. On a narrow terminal, `p` opens full-width previews.

## Environment tags and overrides

New projects start with environment-level `env` and `project` tags. Set **Environment tags · all managed resources** from environment settings (`e` in Resources). The generated provider also uses `default_tags`, and module inputs explicitly merge environment tags with resource overrides. The resource form shows inherited tags as read-only and labels its own tags as overrides. An empty resource tag map means no overrides, not no effective tags. Existing projects retain their chosen tags; EasyTF does not silently replace them.

## ALB and NLB

In Resources, `l` adds an ALB and `b` adds an NLB. Configure subnet IDs, existing/project security groups, frontend listeners, target groups, backend ports, and health checks. Open **Target groups & EC2 targets**, edit a group, then add project EC2 keys from the selection list. Terraform resolves the instance ID (or private IP for IP targets) automatically. No manual copying of Terraform outputs is required.

ALB requires at least two subnets in different AZs and one SG. NLB requires at least one subnet; SGs are optional. Subnets, SGs, and managed EC2 targets must use the same VPC. Existing instance targets use data sources; existing IP targets must be IPv4 addresses. Network routing, SG traffic rules, and the application's health endpoint still require appropriate configuration.

Multiple listeners forward to named target groups. HTTPS/TLS uses an existing certificate ARN. ALB supports HTTP/HTTPS; NLB supports TCP/TLS/UDP/TCP_UDP in this release. HTTP(S) health checks use path/matcher; TCP checks leave them unset. Advanced host/path listener rules, weighted actions, certificate provisioning, access logs, and additional LB options are future extensions.

Attachments reference both target group ARNs and EC2 module outputs, so Terraform creates the dependencies automatically. LB/TG/listener creation can run in parallel with EC2. Attachment keys are built from target group and project EC2 keys, so unknown IDs during plan do not break `for_each`. Deleting an EC2 or SG that a load balancer references is blocked until its links are removed.

Outputs include LB ARN, DNS name, zone ID, listener/TG ARNs, registered target IDs, and effective LB tags. See `examples/ec2-alb-nlb.json` for a linked EC2 + ALB + NLB example with placeholder AWS IDs. Tests under `tests/terraform/load-balancer.tftest.hcl` use a mock provider; they never create AWS resources.

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
python3 tests/tui_lb_smoke.py
```

Terraform requires version 1.10 or newer, below 2.0. The generated AWS provider requirement is `>= 6.68.0, < 7.0`.

## Native macOS application

EasyTF also has a native SwiftUI workspace backed by the same Rust engine. Build with `./scripts/build-macos.sh`, then open `native/build/EasyTF.app`. It supports project/environment setup, EC2, multi-rule SG, and ALB/NLB editors with linked target groups/listeners, read-only AWS pickers, inherited tags, multiple EBS volumes, draft recovery, Terraform preview, and generation. See [native app documentation](native/README.md) for scope and verification.

### Extended native AWS catalog

The macOS app now includes 43 schema-driven AWS resource types covering RDS/Aurora, all EKS compute modes, S3/ECR, IAM/CloudWatch, networking, and DNS/edge. Inputs remain in tfvars; resource output links and explicit dependencies produce separate Terraform module references. See [the native catalog workflow](native/README.md#aws-resource-catalog) and [the complete synthetic fixture](examples/catalog-complete.json).
