variable "prefix" {
  description = "Prefix for all IAM resource names (e.g. 'terraform-lab')"
  type        = string
  default     = "terraform-lab"
}

variable "aws_region" {
  description = "AWS region for DynamoDB ARN scoping"
  type        = string
  default     = "ap-southeast-1"
}

variable "aws_account_id" {
  description = "Your AWS account ID"
  type        = string
}

variable "dynamodb_table" {
  description = "DynamoDB state lock table name"
  type        = string
  default     = "terraform-state-lock"
}

variable "github_org" {
  description = "GitHub organisation or username (for OIDC trust policy)"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (for OIDC trust policy)"
  type        = string
  default     = "terraform-lab"
}

variable "human_principal_arns" {
  description = "List of IAM user/role ARNs allowed to assume developer/auditor/admin roles"
  type        = list(string)
  # Example: ["arn:aws:iam::123456789012:user/aiman"]
}

variable "tags" {
  description = "Tags applied to all IAM resources"
  type        = map(string)
  default = {
    Project   = "terraform-lab"
    ManagedBy = "terraform"
  }
}
