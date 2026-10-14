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
2. **Add resource** creates EC2 or managed security-group entries with stable Terraform keys.
3. EC2 has Basics, Networking, Access, Storage, Tags, and Advanced sections. Browse existing AMIs/subnets/SGs or enter IDs directly. Managed SG references use checkboxes. Tags and multiple EBS volumes have structured editors.
4. SG supports multiple keyed ingress/egress rules. All-traffic rules clear their port values. Dependency checks block removal of resources still referenced by EC2 or ALB/NLB.
5. **Review Terraform** validates inputs and shows generated files and pending file actions. This is a file generation preview, not `terraform plan`.
6. **Generate files** publishes through the existing engine's conflict checks, lock, staging, and recovery journal. No Terraform or AWS infrastructure deployment runs.

EC2, SG, and LB icons use orange, green, and purple. Environment badges use blue for dev, amber for staging, and red for prod. Labels and icons still identify these categories without color.

The first native version preserves existing ALB/NLB configuration and exposes it read-only; use the CLI to edit it. Less common EC2 options are editable as a JSON configuration object under Advanced. Save optional settings before switching sections. Common IAM/keypair/protection and EBS fields have native controls. AWS picker checks are read-only; AMI browsing is limited to Amazon Linux 2023 candidates, while custom IDs can be entered manually. Live AWS discovery was not verified against a real account.

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

Native UI testing covered the wizard/environment/backend choices, EC2 editing, existing AMI picker using a fake AWS CLI, adding a fourth SG ingress rule, preview, and generate. CLI check and `terraform fmt -check` passed on the native-generated project. Rust bridge tests cover EC2 + ALB/NLB round-trip and stale-file rejection. Swift tests cover preserving advanced configuration, default tags, and owner-only draft round-trip.

`EASYTF_DESKTOP_ENGINE` and `EASYTF_DESKTOP_STATE_DIR` override the bundled engine and draft location for development/test fixtures.
