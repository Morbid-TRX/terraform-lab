variable "prefix" {
  description = "Prefix for all IAM resource names (e.g. 'terraform-lab')"
  type        = string
  default     = "terraform-lab"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9\\-]{1,28}[a-z0-9]$", var.prefix))
    error_message = "prefix must be lowercase letters, numbers, and hyphens only (2-30 chars)."
  }
}

variable "aws_region" {
  description = "AWS region for DynamoDB ARN scoping"
  type        = string
  default     = "ap-southeast-1"
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region format (e.g. ap-southeast-1, us-east-1)."
  }
}

variable "aws_account_id" {
  description = "Your AWS account ID (12-digit number)"
  type        = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be exactly 12 digits."
  }
}

variable "dynamodb_table" {
  description = "DynamoDB state lock table name"
  type        = string
  default     = "terraform-state-lock"
  validation {
    condition     = length(var.dynamodb_table) >= 3 && length(var.dynamodb_table) <= 255
    error_message = "dynamodb_table name must be between 3 and 255 characters."
  }
}

variable "github_org" {
  description = "GitHub organisation or username (for OIDC trust policy)"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9\\-]+$", var.github_org))
    error_message = "github_org must contain only letters, numbers, and hyphens."
  }
}

variable "github_repo" {
  description = "GitHub repository name (for OIDC trust policy)"
  type        = string
  default     = "terraform-lab"
  validation {
    condition     = can(regex("^[a-zA-Z0-9_\\.\\-]+$", var.github_repo))
    error_message = "github_repo must contain only letters, numbers, underscores, dots, and hyphens."
  }
}

variable "human_principal_arns" {
  description = "List of IAM user/role ARNs allowed to assume developer/auditor/admin roles"
  type        = list(string)
  validation {
    condition = alltrue([
      for arn in var.human_principal_arns :
      can(regex("^arn:aws:iam::[0-9]{12}:(root|user/|role/).+$", arn))
    ])
    error_message = "All entries in human_principal_arns must be valid IAM ARNs (e.g. arn:aws:iam::123456789012:user/name)."
  }
}

variable "tags" {
  description = "Tags applied to all IAM resources"
  type        = map(string)
  default = {
    Project   = "terraform-lab"
    ManagedBy = "terraform"
  }
}
