terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    s3  = "http://s3.localhost.localstack.cloud:4566"
    ec2 = "http://localhost:4566"
  }
}

module "infrastructure" {
  source      = "../../modules/compute"
  environment = "prod"
  vpc_cidr    = "10.2.0.0/16"
  subnet_cidr = "10.2.1.0/24"
  bucket_name = "prod-terraform-bucket"
  tags = {
    Environment = "Prod"
    Service     = "terraform-lab"
  }
}
