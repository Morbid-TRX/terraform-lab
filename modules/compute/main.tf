###############################################################
# Compute Module — Reusable infrastructure for dev/prod/aws
# Resources: S3 bucket (encrypted, versioned, SSL-enforced,
# public-access blocked), VPC, Subnet
#
# WHY a module? dev, prod, and aws all need identical
# infrastructure. A module enforces consistency and means
# a security fix here applies to all environments at once.
###############################################################

# Variables are declared inline (no separate variables.tf) because
# this module is small and keeping them co-located makes it easier
# to understand what the module expects without jumping between files.
variable "environment" {
  type        = string
  description = "Deployment environment (local, dev, prod, aws)"
  validation {
    condition     = contains(["local", "dev", "prod", "aws"], var.environment)
    error_message = "environment must be one of: local, dev, prod, aws."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC (e.g. 10.0.0.0/16)"
  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for the subnet — must be within vpc_cidr"
  validation {
    condition     = can(cidrhost(var.subnet_cidr, 0))
    error_message = "subnet_cidr must be a valid CIDR block (e.g. 10.0.1.0/24)."
  }
}

variable "bucket_name" {
  type        = string
  description = "S3 bucket name — must follow AWS naming rules"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be 3-63 chars, lowercase letters/numbers/hyphens only, and cannot start or end with a hyphen."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags to merge with default resource tags"
  default     = {}
}

variable "availability_zone" {
  type        = string
  description = "Availability zone for the subnet — must match the provider region"
  default     = "ap-southeast-1a"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9][a-z]$", var.availability_zone))
    error_message = "availability_zone must be a valid AZ format (e.g. ap-southeast-1a, us-east-1a)."
  }
}

########################################
# S3 Bucket — Terraform state storage
#
# WHY so many sub-resources? AWS requires separate resources
# for each S3 feature (versioning, encryption, public access,
# policy). This is by design in the AWS Terraform provider v4+
# to allow independent lifecycle management of each setting.
########################################

resource "aws_s3_bucket" "bucket" {
  # checkov:skip=CKV_AWS_18: Access logging adds S3 storage cost; not justified for lab environment
  # checkov:skip=CKV_AWS_144: Cross-region replication doubles cost; single-region acceptable for lab
  # checkov:skip=CKV_AWS_145: KMS CMK costs $1/key/month; AES256 SSE is enforced via aws_s3_bucket_server_side_encryption_configuration below
  # checkov:skip=CKV2_AWS_62: Event notifications have no consumers in this lab; not applicable
  bucket = var.bucket_name

  # merge() allows callers to inject extra tags (e.g. Project, Owner)
  # while guaranteeing the baseline tags are always present
  tags = merge({
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)

  # WHY prevent_destroy? This bucket holds Terraform state. Accidental
  # destruction would make all managed infrastructure unrecoverable
  # without manual state reconstruction. Remove this flag explicitly
  # if you intend to decommission the environment.
  lifecycle {
    prevent_destroy = true
  }
}

# WHY AES256 and not KMS? AES256 (SSE-S3) is free and encrypts
# data at rest automatically. KMS (SSE-KMS) adds $1/key/month
# and per-request costs — not justified for a lab project.
# Both satisfy encryption-at-rest compliance requirements.
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  # WHY prevent_destroy? Destroying this resource disables encryption
  # at rest on the state bucket — a security regression.
  lifecycle {
    prevent_destroy = true
  }
}

# WHY versioning? Terraform state files are critical. Versioning
# allows recovery if state is accidentally corrupted or deleted.
# Without it, a bad terraform apply could be unrecoverable.
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }

  # WHY prevent_destroy? Destroying this disables versioning — all
  # future state writes become unrecoverable if corrupted or deleted.
  lifecycle {
    prevent_destroy = true
  }
}

# S3 lifecycle policy — automatically manages object versions to
# control storage costs. WHY? Versioning without lifecycle rules
# means old versions accumulate indefinitely, increasing storage cost.
# These rules expire non-current versions after 90 days and clean up
# incomplete multipart uploads after 7 days.
resource "aws_s3_bucket_lifecycle_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    # filter {} is required by AWS provider v4+ — empty filter means
    # "apply this rule to all objects in the bucket". Without it,
    # the provider warns this will become a hard error in future versions.
    filter {}

    # Clean up incomplete multipart uploads after 7 days.
    # WHY? Failed uploads consume storage but are invisible in the console.
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    # Expire non-current object versions after 90 days.
    # WHY 90 days? Balances recovery window (enough time to notice
    # and restore accidental deletions) against storage cost.
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Must be created after versioning is enabled
  depends_on = [aws_s3_bucket_versioning.bucket]
}

# WHY all four settings? Each blocks a different attack vector:
# block_public_acls       — prevents ACL-based public exposure
# block_public_policy     — prevents bucket policy granting public access
# ignore_public_acls      — ignores any existing public ACLs
# restrict_public_buckets — blocks cross-account public access
# All four must be true for complete public access prevention.
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  # WHY create_before_destroy? A gap in public access protection
  # during replacement would briefly expose the bucket. New block
  # must exist before old one is removed.
  lifecycle {
    create_before_destroy = true
  }
}

# WHY a bucket policy for SSL? The public access block above prevents
# public access, but it doesn't enforce encryption in transit.
# This policy explicitly denies any request where SecureTransport
# is false — meaning unencrypted HTTP requests are rejected even
# from authenticated AWS principals within the account.
resource "aws_s3_bucket_policy" "bucket_ssl" {
  bucket = aws_s3_bucket.bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonSSL"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.bucket.arn,
          "${aws_s3_bucket.bucket.arn}/*"
        ]
        Condition = {
          Bool = {
            # aws:SecureTransport is true only for HTTPS requests
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # WHY create_before_destroy? SSL enforcement must never have a gap.
  # If the old policy is destroyed first, unencrypted requests would
  # be briefly accepted.
  lifecycle {
    create_before_destroy = true
  }
}

########################################
# VPC — isolated network boundary
#
# WHY a VPC per environment? Each environment gets its own
# network boundary. Resources in different environments cannot
# communicate by default, preventing accidental cross-env access.
########################################

resource "aws_vpc" "vpc" {
  # checkov:skip=CKV2_AWS_11: VPC flow logging adds CloudWatch Logs ingestion cost; not justified for lab
  # checkov:skip=CKV2_AWS_12: Default SG hardening deferred — no resources use the default SG; explicit SG defined separately in local env

  # CIDR passed as variable so each environment gets its own
  # non-overlapping range (local: 10.0, dev: 10.1, prod: 10.2, aws: 10.3)
  # This makes future VPC peering possible without conflicts.
  cidr_block = var.vpc_cidr
  tags = merge({
    Name        = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}

########################################
# Subnet — single AZ for lab simplicity
#
# WHY single AZ? Multi-AZ requires a NAT Gateway ($32/month)
# or complex routing. For a lab with no EC2 workloads,
# single AZ is sufficient and stays within Free Tier.
########################################

resource "aws_subnet" "subnet" {
  vpc_id     = aws_vpc.vpc.id
  cidr_block = var.subnet_cidr

  # AZ passed as variable — defaults to ap-southeast-1a for real AWS.
  # LocalStack ignores AZ entirely so any value works for local/dev/prod.
  availability_zone = var.availability_zone
  tags = merge({
    Name        = "${var.environment}-subnet"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}
