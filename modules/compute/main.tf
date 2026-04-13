variable "environment" { type = string }
variable "vpc_cidr"    { type = string }
variable "subnet_cidr" { type = string }
variable "bucket_name" { type = string }

resource "aws_s3_bucket" "bucket" {
  bucket = var.bucket_name
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_subnet" "subnet" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = "ap-southeast-1a"
  tags = {
    Name        = "${var.environment}-subnet"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}