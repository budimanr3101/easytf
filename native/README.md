# EasyTF for macOS

Native SwiftUI workspace powered by the existing EasyTF Rust engine. Requires macOS 13+, a Swift/Xcode toolchain to build, and the Rust toolchain used by the CLI. AWS CLI v2 is needed only for live resource browsing.

## Build and run

From the repository root:

```sh
./scripts/build-macos.sh
open native/build/EasyTF.app
```

Open a project directly:

```sh
open native/build/EasyTF.app --args --project /absolute/path/to/project
```

The local development app is signed ad hoc; it is not a notarized distribution. The bundled bridge is `Contents/Resources/easytf-desktop`. It exchanges one JSON request/response per invocation and calls the same model, render, discovery, and transactional publisher as the CLI.

## Workflow

1. **New Project** selects a new folder name, dev/staging/prod environments, AWS region/profile, and local or existing-S3 backend. State keys are separate for every environment.
2. **Add resource** creates EC2, managed security-group, Application Load Balancer, or Network Load Balancer entries with stable Terraform keys.
3. EC2 has Basics, Networking, Access, Storage, Tags, and Advanced sections. Browse existing AMIs/subnets/SGs or enter IDs directly. Managed SG references use checkboxes. Tags and multiple EBS volumes have structured editors.
4. SG supports multiple keyed ingress/egress rules. All-traffic rules clear their port values. Dependency checks block removal of resources still referenced by EC2 or ALB/NLB.
5. **Review Terraform** validates inputs and shows generated files and pending file actions. This is a file generation preview, not `terraform plan`.
6. **Generate files** publishes through the existing engine's conflict checks, lock, staging, and recovery journal. No Terraform or AWS infrastructure deployment runs.

EC2, SG, and LB icons use orange, green, and purple. Environment badges use blue for dev, amber for staging, and red for prod. Labels and icons still identify these categories without color.

ALB/NLB editors include Basics, Networking, Target groups, Listeners, and Tags. Subnet and existing-SG pickers support multiple selections. Each listener selects a named target group. Target groups select project EC2 keys or existing IDs/IPv4s and configure health checks. HTTP/HTTPS and TCP/TLS/UDP/TCP_UDP choices follow the engine's supported protocols. HTTPS/TLS shows certificate ARN and optional SSL policy; switching to a plain protocol clears these fields. TCP health checks clear path/matcher. Target groups cannot be removed while listeners reference them. Removing an LB removes its nested listeners, groups, and attachments from the configuration while preserving EC2 and SG resources.

Less common EC2 options are editable as a JSON configuration object under Advanced. Save optional settings before switching sections. Common IAM/keypair/protection and EBS fields have native controls. AWS picker checks are read-only; AMI browsing is limited to Amazon Linux 2023 candidates, while custom IDs can be entered manually. Live AWS discovery was not verified against a real account.

## Compatibility and drafts

Open projects containing `.easytf.toml`. Arbitrary Terraform project adoption is not supported. Generated output uses the existing `environments/`, `modules/`, `.tfvars`, and backend structure. Manual edits are retained when supported by the loader; generated-file conflicts and edits made after opening are blocked. Existing backend changes require an explicit Terraform migration and are not offered by this editor.

Project edits automatically save an owner-only local draft at `~/Library/Application Support/EasyTF/desktop-draft.json`. **Resume last workspace** restores it. Drafts can include user data and other configuration, so the file is mode 0600. Saving a draft does not write Terraform files. The original observed hashes are retained; resuming a stale project cannot silently overwrite changes made by another editor.

Publishing cannot be cancelled from the UI. If the application/process exits during publication and the engine reports an interrupted transaction, use the CLI's documented `easytf recover --project PATH` before reopening.

## Verification

```sh
cargo test --offline
cargo clippy --offline --all-targets -- -D warnings
swift test --package-path native --build-system native
```

Native UI testing covered the wizard/environment/backend choices, EC2 editing, existing AMI picker using a fake AWS CLI, adding a fourth SG ingress rule, preview, and generate. CLI check and `terraform fmt -check` passed on the native-generated project. Rust bridge tests cover EC2 + ALB/NLB round-trip and stale-file rejection. Swift tests cover preserving advanced configuration, default tags, owner-only draft round-trip, protocol transitions, linked-resource removal guards, and ALB/NLB generation through the Rust bridge. Set EASYTF_DESKTOP_ENGINE to target/debug/easytf-desktop when running the native integration test.

`EASYTF_DESKTOP_ENGINE` and `EASYTF_DESKTOP_STATE_DIR` override the bundled engine and draft location for development/test fixtures.

## AWS resource catalog

The native Add resource menu includes category shortcuts and a searchable catalog of 43 AWS resource types, in addition to the dedicated EC2, SG, ALB, and NLB editors:

- Databases: standalone RDS, Aurora clusters/instances, subnet groups, and parameter groups.
- Kubernetes: EKS clusters, managed node groups, Fargate profiles, addons, and access entries/policy associations. Cluster-only configurations are supported.
- Storage and images: S3 buckets and settings, ECR repositories and lifecycle policies.
- IAM and observability: roles, policies/attachments, instance profiles, CloudWatch logs and alarms.
- Networking: VPCs, subnets, routes, route tables/associations, gateways, NAT/EIP, security groups and rules.
- DNS and edge: Route53 zones/records, ACM certificates/validation, CloudFront distributions and origin access controls.

Required fields appear first. Add optional settings as needed; nested blocks and lists have structured editors. Enter existing AWS IDs directly, or use **Link…** to select compatible outputs from another configured resource. Explicit dependencies are available for ordering that cannot be expressed through an input reference. Deleting a referenced resource is blocked. Resource tags merge with environment defaults.

Literal settings are generated into `.tfvars`. Typed output references and explicit dependencies are generated into `managed-resources.tf`, with one module per resource so Terraform can order dependencies independently. Catalog outputs are exposed through `managed-resources-outputs.tf`. Existing resources entered as literal IDs do not require a data source; the dedicated EC2/SG/LB paths retain their existing discovery/data behavior.

RDS and Aurora defaults enable AWS-managed master credentials, encryption, and deletion protection. Sensitive and write-only provider attributes are excluded from the generic editor. Existing credential ARNs or other sensitive configuration still need appropriate handling by the user. The catalog is derived from AWS provider 6.68.0; provider constraints, IAM permissions, DNS validation records, network reachability, and application-specific policies must be configured for the intended deployment.

`examples/catalog-complete.json` is a synthetic validation fixture with 49 resources covering all 43 catalog types, not a production deployment blueprint. It passed Terraform formatting, provider validation, and an offline mocked plan; no AWS deployment was performed.

Catalog maintenance: obtain the provider schema at `test-output/aws-schema.json`, then run `python3 scripts/build-resource-catalog.py`, `cargo fmt`, and `terraform fmt -recursive templates/catalog`. Regenerate the fixture with `python3 scripts/build-catalog-example.py`. The schema, module templates, and Rust template inventory are checked in.
