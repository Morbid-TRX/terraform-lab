###############################################################
# Compute Module — Reusable infrastructure for dev/prod/aws
# Resources: S3 bucket (encrypted, versioned, SSL-enforced,
# public-access blocked), VPC, Subnet
###############################################################

variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_cidr" { type = string }
variable "bucket_name" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

########################################
# S3 Bucket — state storage
########################################

resource "aws_s3_bucket" "bucket" {
  # checkov:skip=CKV_AWS_18: Access logging adds S3 storage cost; not justified for lab environment
  # checkov:skip=CKV_AWS_144: Cross-region replication doubles cost; single-region acceptable for lab
  # checkov:skip=CKV_AWS_145: KMS CMK costs $1/key/month; AES256 SSE is enforced via aws_s3_bucket_server_side_encryption_configuration below
  # checkov:skip=CKV2_AWS_61: Lifecycle configuration deferred to TODO #8 (lifecycle rules on critical resources)
  # checkov:skip=CKV2_AWS_62: Event notifications have no consumers in this lab; not applicable
  bucket = var.bucket_name
  tags = merge({
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}

# Enforce server-side encryption (AES256)
resource "aws_s3_bucket_server_side_encryption_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning — protects against accidental deletion/overwrite
resource "aws_s3_bucket_versioning" "bucket" {
  bucket = aws_s3_bucket.bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Block all public access at bucket level
resource "aws_s3_bucket_public_access_block" "bucket" {
  bucket = aws_s3_bucket.bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Deny any non-SSL requests to the bucket
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
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

########################################
# VPC
########################################

resource "aws_vpc" "vpc" {
  # checkov:skip=CKV2_AWS_11: VPC flow logging adds CloudWatch Logs ingestion cost; not justified for lab
  # checkov:skip=CKV2_AWS_12: Default SG hardening deferred — no resources use the default SG; explicit SG defined separately in local env
  cidr_block = var.vpc_cidr
  tags = merge({
    Name        = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}

########################################
# Subnet
########################################

resource "aws_subnet" "subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = "ap-southeast-1a"
  tags = merge({
    Name        = "${var.environment}-subnet"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}
