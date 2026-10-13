# EasyTF roadmap

## Delivered

- Rust CLI/TUI and multi-environment Terraform generation.
- Existing subnet/SG references and managed/shared SG dependencies.
- Local/S3 backend configuration, tfvars, and output definitions.
- Preview/diff, protected regeneration, drafts, and interrupted-publish recovery.
- Visible form actions, environment continuation action, and keyboard regression tests.
- Read-only subnet/SG discovery and an Amazon Linux 2023 AMI picker; manual IDs remain available.
- Background discovery, search, selection, cancellation, and credential error handling.

- Multi-rule ingress/egress and structured tag editing.
- Six optional EC2 sections, IAM role/profile and key pair support, multi-EBS, metadata/CPU/launch/network blocks.

## Next

1. Terraform command integration: fmt, init, validate, plan, streaming logs and cancellation.
2. Applied output values through terraform output -json.
3. Explicit AWS dependency verification beyond picker filtering, including AMI/instance architecture compatibility.
4. Per-project drafts and recovery of unfinished forms.
5. Copy resources between environments with controlled overrides.
6. Explicit backend migration workflow.
7. Additional resource generators (networking, ALB, RDS).
8. Existing manual Terraform project adoption/import.
9. GitHub remote, CI, packaging, and macOS/Linux releases.

AWS discovery is covered by fixture CLI tests and actual PTY interaction tests; a live account/SSO validation is still pending. AMI browsing is currently limited to the first 200 Amazon Linux 2023 results. No apply/destroy functionality has been added.
