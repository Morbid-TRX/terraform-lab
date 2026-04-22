###############################################################
# Dev Environment — LocalStack (Docker)
#
# WHY LocalStack for dev? Mirrors the local environment for
# shared development testing without touching real AWS.
# Uses the compute module to stay consistent with prod and aws.
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
# AWS credentials — any non-empty value works. See local/main.tf
# for full explanation of each skip setting.
provider "aws" {
  access_key = "test"
  secret_key = "test"
  # us-east-1 is the LocalStack default region — actual region
  # doesn't matter for local emulation, only for real AWS deployment.
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://s3.localhost.localstack.cloud:4566"
    ec2 = "http://localhost:4566"
  }
}

# WHY 10.1.0.0/16? Each environment gets a non-overlapping CIDR:
# local=10.0, dev=10.1, prod=10.2, aws=10.3
# This allows future VPC peering without address conflicts.
module "infrastructure" {
  source      = "../../modules/compute"
  environment = "dev"
  vpc_cidr    = "10.1.0.0/16"
  subnet_cidr = "10.1.1.0/24"
  bucket_name = "dev-terraform-bucket"
  tags = {
    Environment = "Dev"
    Service     = "terraform-lab"
  }
}
