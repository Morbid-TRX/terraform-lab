terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

module "infrastructure" {
  source      = "../../modules/compute"
  environment = "aws"
  vpc_cidr    = "10.3.0.0/16"
  subnet_cidr = "10.3.1.0/24"
  bucket_name = "aiman-terraform-aws-bucket"
  tags = {
    Environment = "Prod"
    Service     = "terraform-lab"
  }
}

module "iam_access_model" {
  source = "../../modules/iam-access-model"

  prefix         = "terraform-lab"
  aws_region     = "ap-southeast-1"
  aws_account_id = var.aws_account_id
  dynamodb_table = "terraform-state-lock"

  github_org  = "Morbid-TRX"
  github_repo = "terraform-lab"

  human_principal_arns = [
    "arn:aws:iam::${var.aws_account_id}:root"
  ]

  tags = {
    Project     = "terraform-lab"
    Environment = "Prod"
    Service     = "terraform-lab"
    ManagedBy   = "terraform"
  }
}
