# Terraform Infrastructure Lab

A multi-environment cloud infrastructure project using Terraform and LocalStack, featuring automated drift detection, drift simulation, and a GitHub Actions CI pipeline.

## What This Project Does

Provisions AWS-compatible infrastructure locally across isolated dev, prod, and local environments using reusable Terraform modules — with a Python-based drift detection system that runs automatically on every push via GitHub Actions.

## Infrastructure Provisioned

- **VPC** — isolated private network per environment
- **Subnet** — public subnet within each VPC
- **Security Group** — ingress rules for SSH and HTTP (local environment)
- **S3 Bucket** — object storage bucket per environment

## Environment Structure

| Environment | VPC CIDR | Bucket |
|---|---|---|
| local | 10.0.0.0/16 | my-terraform-bucket |
| dev | 10.1.0.0/16 | dev-terraform-bucket |
| prod | 10.2.0.0/16 | prod-terraform-bucket |

## AWS Deployment Validation

The same Terraform module was successfully deployed to **real AWS** (ap-southeast-1, Singapore) with zero code modifications — validating true cloud portability.

Resources provisioned on AWS:
- VPC (`10.3.0.0/16`) — ap-southeast-1
- Subnet — ap-southeast-1a
- S3 Bucket (`aiman-terraform-aws-bucket`) — ap-southeast-1

> Infrastructure was provisioned and verified on AWS Free Tier, then destroyed to avoid charges.

## Tools & Technologies

- **Terraform** — Infrastructure as Code
- **LocalStack** — local AWS cloud emulator (via Docker)
- **Python** — drift detection and simulation scripts
- **Docker** — container runtime for LocalStack
- **GitHub Actions** — CI pipeline for automated drift checks
- **Git** — version control

## Project Structure

```
terraform-lab/
├── .github/
│   └── workflows/
│       └── drift-check.yml     # CI pipeline
├── environments/
│   ├── local/
│   │   ├── main.tf             # local environment config
│   │   ├── variables.tf        # input variables
│   │   └── outputs.tf          # resource outputs
│   ├── dev/
│   │   └── main.tf             # dev environment config
│   └── prod/
│       └── main.tf             # prod environment config
├── modules/
│   └── compute/
│       ├── main.tf             # reusable infrastructure module
│       └── variables.tf        # module input variables
├── drift_detector.py           # scans for infrastructure drift
├── drift_simulator.py          # simulates out-of-band changes
├── .gitignore
└── README.md
```

## How to Run

### 1. Start LocalStack
```bash
docker run -d -p 4566:4566 -p 4510-4559:4510-4559 \
  --name localstack \
  -e LOCALSTACK_AUTH_TOKEN=your_token \
  localstack/localstack
```

### 2. Provision an Environment
```bash
cd environments/local   # or dev, or prod
terraform init
terraform apply
```

### 3. Run Drift Detection
```bash
python drift_detector.py
```

### 4. Simulate Drift
```bash
python drift_simulator.py           # breaks infra
python drift_detector.py            # catches it
python drift_simulator.py restore   # restores clean state
```

## CI Pipeline

The GitHub Actions pipeline runs automatically on every push to `main` and daily at 8:00 AM UTC. It spins up LocalStack, provisions infrastructure, and runs the drift detector — reporting clean or drift status in the workflow logs.

## Key Concepts Demonstrated

- Multi-environment Infrastructure as Code with reusable Terraform modules
- Parameterized infrastructure using variables and outputs
- Local cloud emulation for cost-free development and testing
- Automated drift detection mimicking enterprise SRE workflows
- State management and resource lifecycle operations
- CI/CD pipeline integration with GitHub Actions