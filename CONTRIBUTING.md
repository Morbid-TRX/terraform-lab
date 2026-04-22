# Contributing to terraform-lab

This document explains how to work on this project — environment setup,
branch workflow, running things locally, and how CI works.

---

## Prerequisites

Make sure you have these installed before starting:

| Tool | Purpose | Install |
|------|---------|---------|
| Terraform | IaC provisioning | https://developer.hashicorp.com/terraform/install |
| Python 3.11+ | Drift detector + simulator | https://www.python.org/downloads/ |
| Docker Desktop | LocalStack container | https://www.docker.com/products/docker-desktop |
| pre-commit | Local git hooks | `pip install pre-commit` |
| Checkov | IaC security scanner | `pip install checkov` |
| aws-vault | Secure credential storage | https://github.com/99designs/aws-vault |
| Git | Version control | https://git-scm.com |

---

## Initial setup

### 1. Clone the repo

```bash
git clone https://github.com/Morbid-TRX/terraform-lab.git
cd terraform-lab
```

### 2. Install pre-commit hooks

```bash
pre-commit install
```

This installs hooks that run automatically on every `git commit`:
- `terraform fmt` — auto-formats Terraform files
- `terraform validate` — validates Terraform syntax
- `end-of-file-fixer` — ensures files end with a newline
- `gitleaks` — scans for hardcoded secrets
- `Checkov` — IaC security scanner

### 3. Set up your environment variables

Copy the example tfvars file and fill in your values:

```bash
cp environments/aws/terraform.tfvars.example environments/aws/terraform.tfvars
```

Then edit `terraform.tfvars` and fill in:
- `aws_account_id` — your 12-digit AWS account ID

> ⚠️ `terraform.tfvars` is gitignored. Never commit it.

### 4. Set up aws-vault (for real AWS work only)

```bash
aws-vault add terraform-lab
```

Enter your AWS access key and secret key when prompted. Then use:

```bash
aws-vault exec terraform-lab -- terraform apply
```

For LocalStack development, aws-vault is not needed — credentials are
hardcoded as `test/test` in `environments/local/main.tf`.

---

## Branch workflow

This project uses **branch protection** — you cannot push directly to `main`.
All changes must go through a pull request.

```bash
main (protected)
 └── your-branch → PR → CI must pass → merge
```

### Naming conventions

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/description` | `feat/add-lifecycle-rules` |
| Bug fix | `fix/description` | `fix/drift-detector-timezone` |
| Docs | `docs/description` | `docs/contributing` |
| Chore | `chore/description` | `chore/update-pre-commit` |

### Step-by-step

```bash
# 1. Always branch from latest main
git checkout main
git pull origin main
git checkout -b feat/your-feature

# 2. Make your changes, then commit
git add .
git commit -m "feat: describe what you did"
# pre-commit hooks run automatically here

# 3. If hooks auto-fix files, stage and re-commit
git add .
git commit -m "chore: apply pre-commit auto-fixes"

# 4. Push and open a PR
git push -u origin feat/your-feature
```

Then open the PR on GitHub, wait for CI to pass, and merge.

---

## Environments

| Environment | Location | Backend | Purpose |
|-------------|----------|---------|---------|
| `local` | `environments/local` | LocalStack | Local development, no AWS needed |
| `dev` | `environments/dev` | S3 + DynamoDB | Shared dev environment |
| `prod` | `environments/prod` | S3 + DynamoDB | Production (careful!) |
| `aws` | `environments/aws` | S3 + DynamoDB | Real AWS, includes IAM model |

### Running locally (LocalStack)

Make sure Docker Desktop is running, then:

```bash
# Start LocalStack
docker run -d -p 4566:4566 --name localstack localstack/localstack

# Init and apply
cd environments/local
terraform init
terraform apply
```

### Running the drift detector

```bash
python drift_detector.py
```

Requires `SLACK_WEBHOOK_URL` set in your environment if you want Slack alerts.
Runs silently and prints to stdout if no webhook is configured.

---

## CI/CD pipeline

CI runs automatically on every push and pull request to `main`.

| Step | Tool | Fail behavior |
|------|------|--------------|
| Cost estimate | Infracost | Non-blocking |
| IaC security scan | tfsec | Non-blocking (soft fail) |
| IaC security scan | Checkov | **Blocking** (hard fail) |
| LocalStack deploy | Terraform | Blocking |
| Drift detection | drift_detector.py | Blocking |
| Scheduled remediation | Terraform | Blocking (schedule only) |

> Checkov is the stricter gate — any unsuppressed finding blocks the merge.
> tfsec findings are reported but do not block.

### Suppressing a Checkov finding

If Checkov flags something that is intentionally acceptable, suppress it
**inline** with a justification comment:

```hcl
resource "aws_s3_bucket" "example" {
  # checkov:skip=CKV_AWS_18: Access logging not needed for this lab environment
  bucket = "my-bucket"
}
```

Never suppress without a reason. The justification is required for review.

---

## Security

- **No secrets in code** — all sensitive values go in `terraform.tfvars` (gitignored)
- **gitleaks** runs on every commit to catch accidental secret exposure
- **aws-vault** stores AWS credentials encrypted in the OS keychain
- **OIDC** is used for CI/CD — no static AWS keys in GitHub secrets
- AWS account ID lives only in `terraform.tfvars` (never committed)

---

## Project structure

```
terraform-lab/
├── .github/workflows/      # CI/CD pipelines
│   ├── drift-check.yml     # Main CI + scheduled drift check
│   └── remediate.yml       # Manual remediation workflow
├── environments/
│   ├── local/              # LocalStack (Docker)
│   ├── dev/                # AWS dev environment
│   ├── prod/               # AWS prod environment
│   └── aws/                # Real AWS + IAM access model
├── modules/
│   ├── compute/            # Reusable VPC + S3 + Subnet module
│   └── iam-access-model/   # 4-persona IAM model (Developer, CI/CD, Admin, Auditor)
├── drift_detector.py       # Drift detection + Slack alerts
├── drift_simulator.py      # Simulates drift for testing
├── .checkov.yaml           # Checkov configuration
├── .pre-commit-config.yaml # Pre-commit hook configuration
└── README.md               # Project overview
```

---

## Questions?

This is a solo learning project. If you're reading this, you're probably
future-me — check `README.md` for the high-level overview, and the
git log for context on why things were built the way they were.
