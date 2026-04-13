# Terraform Infrastructure Lab

A local cloud infrastructure project using Terraform and LocalStack, featuring automated drift detection and simulation.

## What This Project Does

Provisions a multi-resource AWS-compatible environment locally and detects configuration drift using a custom Python script — simulating real-world IaC operations without cloud costs.

## Infrastructure Provisioned

- **VPC** — isolated private network (CIDR: 10.0.0.0/16)
- **Subnet** — public subnet within the VPC
- **Security Group** — ingress rules for SSH and HTTP
- **S3 Bucket** — object storage bucket

## Tools & Technologies

- **Terraform** — Infrastructure as Code
- **LocalStack** — local AWS cloud emulator (via Docker)
- **Python** — drift detection and simulation scripts
- **Docker** — container runtime for LocalStack
- **Git** — version control

## Project Structure

terraform-lab/
├── environments/
│   └── local/
│       └── main.tf
├── modules/
│   └── compute/
├── drift_detector.py
├── drift_simulator.py
├── .gitignore
└── README.md

## How to Run

### 1. Start LocalStack
```bash
docker run -d -p 4566:4566 -p 4510-4559:4510-4559 \
  --name localstack \
  -e LOCALSTACK_AUTH_TOKEN=your_token \
  localstack/localstack
```

### 2. Provision Infrastructure
```bash
cd environments/local
terraform init
terraform apply
```

### 3. Run Drift Detection
```bash
python drift_detector.py
```

### 4. Simulate Drift
```bash
python drift_simulator.py         # breaks infra
python drift_detector.py          # catches it
python drift_simulator.py restore # restores clean state
```

## Key Concepts Demonstrated

- Infrastructure as Code with modular Terraform structure
- Local cloud emulation for cost-free development
- Automated drift detection mimicking enterprise SRE workflows
- State management and resource lifecycle operations