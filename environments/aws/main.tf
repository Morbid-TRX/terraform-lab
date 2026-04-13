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
}