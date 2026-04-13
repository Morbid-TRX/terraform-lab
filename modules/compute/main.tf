variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_cidr" { type = string }
variable "bucket_name" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  tags = merge({
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}

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

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags = merge({
    Name        = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
    Service     = "terraform-lab"
  }, var.tags)
}

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
