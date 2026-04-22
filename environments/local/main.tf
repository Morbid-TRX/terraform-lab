###############################################################
# Local Environment — LocalStack (Docker)
#
# WHY LocalStack? Allows full Terraform development and testing
# without touching real AWS. Resources are emulated locally,
# so there's zero cost and no risk of accidental AWS charges.
#
# WHY not use the compute module here? The local environment
# predates the module and includes a Security Group for testing
# network rules — something the compute module doesn't have.
# Kept separate intentionally to test SG behaviour locally.
###############################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# WHY hardcoded test credentials? LocalStack doesn't validate
# AWS credentials — any non-empty value works. These are the
# LocalStack-recommended dummy values, not real AWS keys.
# Real credentials are never used in local environment.
provider "aws" {
  access_key = "test"
  secret_key = "test"
  region     = "us-east-1"

  # These skips are required for LocalStack — the provider would
  # otherwise try to validate credentials against real AWS endpoints
  # which would fail since we're pointing at localhost.
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  # Override AWS service endpoints to point at LocalStack containers.
  # LocalStack runs on port 4566 and emulates the AWS API surface.
  endpoints {
    s3  = "http://s3.localhost.localstack.cloud:4566"
    ec2 = "http://localhost:4566"
  }
}

########################################
# S3 Bucket — local state storage
########################################

resource "aws_s3_bucket" "my_bucket" {
  # checkov:skip=CKV_AWS_18: Access logging adds S3 storage cost; not justified for LocalStack lab
  # checkov:skip=CKV_AWS_144: Cross-region replication not applicable to LocalStack single-endpoint setup
  # checkov:skip=CKV_AWS_145: KMS CMK costs $1/key/month; AES256 SSE enforced via aws_s3_bucket_server_side_encryption_configuration below
  # checkov:skip=CKV2_AWS_61: Lifecycle configuration deferred to TODO #8 (lifecycle rules on critical resources)
  # checkov:skip=CKV2_AWS_62: Event notifications have no consumers in this lab; not applicable
  bucket = var.bucket_name

  tags = {
    Name        = var.bucket_name
    Environment = "Dev"
    Service     = "terraform-lab"
    ManagedBy   = "terraform"
  }
}

# Protects against accidental state file deletion or corruption.
# Versioning allows point-in-time recovery of Terraform state.
resource "aws_s3_bucket_versioning" "my_bucket_versioning" {
  bucket = aws_s3_bucket.my_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# AES256 (SSE-S3) encrypts all objects at rest automatically.
# Chosen over KMS to avoid per-request costs on a lab budget.
resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket_encryption" {
  bucket = aws_s3_bucket.my_bucket.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# All four settings required for complete public access prevention.
# See compute module for explanation of each individual setting.
resource "aws_s3_bucket_public_access_block" "my_bucket_public_access" {
  bucket                  = aws_s3_bucket.my_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforces encryption in transit. Denies any S3 request made
# over HTTP (SecureTransport = false), even from authenticated principals.
resource "aws_s3_bucket_policy" "my_bucket_ssl" {
  bucket = aws_s3_bucket.my_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

########################################
# VPC — isolated network for local dev
########################################

resource "aws_vpc" "my_vpc" {
  # checkov:skip=CKV2_AWS_11: VPC flow logging adds CloudWatch Logs cost; not available in LocalStack free tier
  # checkov:skip=CKV2_AWS_12: Default SG unused — all traffic routed through explicit aws_security_group.my_sg below
  cidr_block = var.vpc_cidr

  tags = {
    Name        = "my-terraform-vpc"
    Environment = "Dev"
    Service     = "terraform-lab"
    ManagedBy   = "terraform"
  }
}

# Single AZ — sufficient for local testing with no real workloads.
# availability_zone uses us-east-1a to match LocalStack's default region.
resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = "us-east-1a"

  tags = {
    Name        = "my-terraform-subnet"
    Environment = "Dev"
    Service     = "terraform-lab"
    ManagedBy   = "terraform"
  }
}

########################################
# Security Group — network access control
#
# WHY defined here and not in the compute module? Security Groups
# are environment-specific. Local uses permissive-ish rules for
# development convenience. Prod would use stricter rules.
# Keeping SG out of the module preserves this flexibility.
########################################

resource "aws_security_group" "my_sg" {
  # checkov:skip=CKV2_AWS_5: SG is attached to VPC; Checkov flags it because no EC2/RDS consumer exists (LocalStack free tier does not support EC2). SG is intentionally defined for VPC-level network boundary.
  name        = "my-terraform-sg"
  description = "Security group managed by Terraform"
  vpc_id      = aws_vpc.my_vpc.id

  # WHY only VPC CIDR for ingress? Restricts SSH and HTTP access
  # to within the VPC only — no public internet exposure.
  # In a real environment, SSH would be replaced with SSM Session Manager.
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow SSH from within VPC only"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTP from within VPC only"
  }

  # WHY only port 443 for egress? Least-privilege egress — only
  # HTTPS outbound is permitted. Blocks unexpected outbound traffic
  # on other ports (e.g. data exfiltration over non-standard ports).
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Allow HTTPS outbound within VPC only"
  }

  tags = {
    Name        = "my-terraform-sg"
    Environment = "Dev"
    Service     = "terraform-lab"
    ManagedBy   = "terraform"
  }
}
