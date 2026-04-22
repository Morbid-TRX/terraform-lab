# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

---

## [0.6.0] - 2026-04-22

### Added
- Bandit Python security scanner for `drift_detector.py` and `drift_simulator.py`
- Bandit pre-commit hook pinned to `1.9.4`
- Bandit step in CI pipeline (`drift-check.yml`)
- `.bandit` config file with justified skip list (B404, B603, B607, B310)
- CONTRIBUTING.md — full contributor guide with prerequisites, branch workflow,
  environment table, CI/CD pipeline table, and suppression instructions
- CHANGELOG.md — versioned history from v0.1.0 onwards
- Inline WHY comments across all `.tf` files explaining design decisions
- Variable validation rules on compute module (environment, vpc_cidr,
  subnet_cidr, bucket_name) and IAM access model module (prefix, aws_region,
  aws_account_id, dynamodb_table, github_org, github_repo, human_principal_arns)
- S3 lifecycle configuration on all buckets — 90-day non-current version
  expiry, 7-day incomplete multipart upload cleanup
- Terraform `lifecycle` blocks on critical resources:
  - `prevent_destroy = true` on S3 bucket, versioning, and SSE configuration
  - `create_before_destroy = true` on public access block, bucket policy, and security group

### Fixed
- Removed stale `CKV2_AWS_61` checkov:skip comments now that lifecycle
  configuration is implemented

### Security
- Checkov score improved: 133 passed, 0 failed, 23 skipped (all justified)
- Bad inputs now caught at `terraform plan` time with human-readable errors
  instead of failing during apply with cryptic AWS API errors
- Critical resources protected against accidental destruction via
  `prevent_destroy` lifecycle rules

---

## [0.5.0] - 2026-04-21

### Added
- Checkov IaC scanner alongside tfsec (defense-in-depth)
- `.checkov.yaml` configuration with justified skip list
- Checkov step in CI pipeline (`drift-check.yml`) with `soft_fail: false`
- Checkov pre-commit hook pinned to `3.2.524`
- gitleaks secret scanning in pre-commit hooks

### Fixed
- `modules/compute` was missing S3 versioning, public access block, and
  SSE encryption — affected dev, prod, and aws environments
- 25 inline `checkov:skip` suppressions added with justifications across
  local environment, compute module, and IAM access model

### Security
- All 27 Checkov findings triaged: 6 real fixes applied, 21 suppressed
  with documented justifications
- Results: 129 passed, 0 failed, 25 skipped

---

## [0.4.0] - 2026-04-14

### Added
- aws-vault integration for secure local credential storage
- `terraform.tfvars.example` documented for aws environment
- IAM access model — 4 personas with least-privilege policies:
  - Developer (full dev, read-only prod)
  - CI/CD (OIDC, no static keys, all environments)
  - Admin (full access, MFA required)
  - Auditor (read-only, explicit Deny on writes)
- DynamoDB lock scoping per environment
- OIDC provider for GitHub Actions (no static AWS credentials in CI)

### Security
- MFA enforced on Admin role assumption
- Explicit Deny statement on Auditor role
- No static AWS keys anywhere — OIDC for CI/CD, aws-vault for local

---

## [0.3.0] - 2026-04-13

### Added
- CI/CD pipeline via GitHub Actions (`drift-check.yml`, `remediate.yml`)
- tfsec security scanning in CI
- Infracost cost estimation in CI
- pre-commit hooks: `terraform fmt`, `terraform validate`,
  `end-of-file-fixer`, `check-yaml`, `check-merge-conflict`
- Branch protection: PR required, CI must pass, no direct pushes to main
- Smart remediation: auto on schedule, manual approval on push
- Slack alerts: drift detected, clean, remediation complete,
  cost threshold exceeded, pipeline failure

### Security
- tfsec reduced from 12 findings to 3 acceptable suppressions
- SSL enforced on all S3 buckets via bucket policy
- Branch protection prevents direct commits to main

---

## [0.2.0] - 2026-04-13

### Added
- Python drift detector (`drift_detector.py`) with Slack alerts
- Python drift simulator (`drift_simulator.py`) for testing
- Source tracking and MYT (UTC+8) timestamps in all alerts
- Daily scheduled drift check at 7PM MYT (11:00 UTC cron)

---

## [0.1.0] - 2026-04-13

### Added
- Multi-environment Terraform IaC: local, dev, prod, aws
- Reusable `compute` module: VPC, Subnet, Security Group, S3
- S3 bucket hardening: encrypted (AES256), versioned, SSL-enforced,
  public access blocked
- LocalStack setup for local AWS emulation via Docker
- Validated on real AWS ap-southeast-1, then destroyed
- FinOps-compliant resource tagging across all environments
- Remote state: S3 backend + DynamoDB locking

### Security
- No hardcoded secrets anywhere in code or git history
- AWS account ID only in gitignored `terraform.tfvars`

---

[Unreleased]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/Morbid-TRX/terraform-lab/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/Morbid-TRX/terraform-lab/releases/tag/v0.1.0
