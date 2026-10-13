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
```

Terraform requires version 1.10 or newer, below 2.0. The generated AWS provider requirement is `~> 6.0`.
