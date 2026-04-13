###############################################################
# IAM — Company-grade Access Model
# Personas: Developer, CI/CD (OIDC), Admin, Auditor
# Project: terraform-lab (local / dev / prod / aws)
###############################################################

locals {
  # All environment state buckets
  all_buckets = [
    "arn:aws:s3:::my-terraform-bucket",
    "arn:aws:s3:::dev-terraform-bucket",
    "arn:aws:s3:::prod-terraform-bucket",
    "arn:aws:s3:::aiman-terraform-aws-bucket",
  ]
  all_bucket_objects = [for b in local.all_buckets : "${b}/*"]

  # Non-prod only (local + dev)
  dev_buckets = [
    "arn:aws:s3:::my-terraform-bucket",
    "arn:aws:s3:::dev-terraform-bucket",
  ]
  dev_bucket_objects = [for b in local.dev_buckets : "${b}/*"]

  dynamo_arn = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.dynamodb_table}"
}

########################################
# 1. DEVELOPER ROLE
#    - Full access: local + dev
#    - Read-only:   prod + aws
########################################

resource "aws_iam_role" "developer" {
  name               = "${var.prefix}-developer"
  description        = "Human developer - full dev access, read-only prod"
  assume_role_policy = data.aws_iam_policy_document.assume_human.json
  tags               = merge(var.tags, { Role = "developer" })
}

data "aws_iam_policy_document" "developer" {
  # Full S3 access to dev/local buckets
  statement {
    sid       = "DevS3Full"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = concat(local.dev_buckets, local.dev_bucket_objects)
  }

  # Read-only S3 access to prod/aws buckets
  statement {
    sid     = "ProdS3ReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = [
      "arn:aws:s3:::prod-terraform-bucket",
      "arn:aws:s3:::prod-terraform-bucket/*",
      "arn:aws:s3:::aiman-terraform-aws-bucket",
      "arn:aws:s3:::aiman-terraform-aws-bucket/*",
    ]
  }

  # DynamoDB lock — dev only (cannot lock prod)
  statement {
    sid    = "DevDynamoLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [local.dynamo_arn]
    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["local/*", "dev/*"]
    }
  }

  # Core Terraform plan permissions (VPC, S3, SG, Subnet)
  statement {
    sid    = "TerraformReadForPlan"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
    ]
    resources = ["*"]
  }

  # Terraform apply — dev/local only
  statement {
    sid    = "TerraformApplyDev"
    effect = "Allow"
    actions = [
      "ec2:CreateVpc", "ec2:DeleteVpc",
      "ec2:CreateSubnet", "ec2:DeleteSubnet",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags", "ec2:DeleteTags",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.aws_region]
    }
  }
}

resource "aws_iam_policy" "developer" {
  name   = "${var.prefix}-developer-policy"
  policy = data.aws_iam_policy_document.developer.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "developer" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.developer.arn
}

########################################
# 2. CI/CD ROLE (GitHub Actions OIDC)
#    - Deploy access to ALL environments
#    - No long-lived credentials
########################################

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
  tags            = var.tags
}

resource "aws_iam_role" "cicd" {
  name               = "${var.prefix}-cicd"
  description        = "GitHub Actions CI/CD - OIDC, no static keys"
  assume_role_policy = data.aws_iam_policy_document.assume_github_oidc.json
  tags               = merge(var.tags, { Role = "cicd" })
}

data "aws_iam_policy_document" "assume_github_oidc" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "cicd" {
  # Full state access across all environments
  statement {
    sid       = "CICDS3StateAll"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = concat(local.all_buckets, local.all_bucket_objects)
  }

  # DynamoDB lock — all environments
  statement {
    sid    = "CICDDynamoLock"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:DescribeTable",
    ]
    resources = [local.dynamo_arn]
  }

  # Terraform plan + apply permissions
  statement {
    sid    = "CICDTerraformApplyAll"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:CreateVpc", "ec2:DeleteVpc",
      "ec2:CreateSubnet", "ec2:DeleteSubnet",
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
      "ec2:CreateTags", "ec2:DeleteTags",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPolicy",
    ]
    resources = ["*"]
  }

  # Drift detector — read-only describe across all envs
  statement {
    sid    = "DriftDetectorRead"
    effect = "Allow"
    actions = [
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "s3:ListAllMyBuckets",
      "s3:GetBucketLocation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "cicd" {
  name   = "${var.prefix}-cicd-policy"
  policy = data.aws_iam_policy_document.cicd.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "cicd" {
  role       = aws_iam_role.cicd.name
  policy_arn = aws_iam_policy.cicd.arn
}

########################################
# 3. ADMIN ROLE
#    - Full access everywhere
#    - IAM management included
#    - Requires MFA
########################################

resource "aws_iam_role" "admin" {
  name               = "${var.prefix}-admin"
  description        = "Infrastructure admin - full access, MFA required"
  assume_role_policy = data.aws_iam_policy_document.assume_human_mfa.json
  tags               = merge(var.tags, { Role = "admin" })
}

data "aws_iam_policy_document" "admin" {
  # Full S3 state access
  statement {
    sid       = "AdminS3Full"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = concat(local.all_buckets, local.all_bucket_objects)
  }

  # Full DynamoDB lock access
  statement {
    sid       = "AdminDynamoFull"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = [local.dynamo_arn]
  }

  # Full EC2 (VPC, Subnet, SG, etc.)
  statement {
    sid       = "AdminEC2Full"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  # IAM management (scoped to project prefix)
  statement {
    sid    = "AdminIAMScoped"
    effect = "Allow"
    actions = [
      "iam:CreateRole", "iam:DeleteRole", "iam:UpdateRole",
      "iam:AttachRolePolicy", "iam:DetachRolePolicy",
      "iam:CreatePolicy", "iam:DeletePolicy",
      "iam:PassRole", "iam:GetRole", "iam:ListRoles",
      "iam:TagRole", "iam:UntagRole",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/${var.prefix}-*",
      "arn:aws:iam::${var.aws_account_id}:policy/${var.prefix}-*",
    ]
  }
}

resource "aws_iam_policy" "admin" {
  name   = "${var.prefix}-admin-policy"
  policy = data.aws_iam_policy_document.admin.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.admin.name
  policy_arn = aws_iam_policy.admin.arn
}

########################################
# 4. AUDITOR ROLE
#    - Read-only across ALL environments
#    - No write, no lock, no IAM changes
########################################

resource "aws_iam_role" "auditor" {
  name               = "${var.prefix}-auditor"
  description        = "Read-only auditor - view state and infra, no writes"
  assume_role_policy = data.aws_iam_policy_document.assume_human.json
  tags               = merge(var.tags, { Role = "auditor" })
}

data "aws_iam_policy_document" "auditor" {
  statement {
    sid    = "AuditorS3ReadOnly"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketVersioning",
      "s3:GetBucketPolicy",
      "s3:GetEncryptionConfiguration",
      "s3:GetBucketPublicAccessBlock",
    ]
    resources = concat(local.all_buckets, local.all_bucket_objects)
  }

  statement {
    sid    = "AuditorDynamoReadOnly"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:DescribeTable",
      "dynamodb:Scan",
    ]
    resources = [local.dynamo_arn]
  }

  statement {
    sid    = "AuditorEC2ReadOnly"
    effect = "Allow"
    actions = [
      "ec2:Describe*",
      "ec2:Get*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AuditorIAMReadOnly"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  # Explicit deny — no writes ever
  statement {
    sid    = "DenyAllWrites"
    effect = "Deny"
    actions = [
      "s3:PutObject", "s3:DeleteObject",
      "ec2:Create*", "ec2:Delete*", "ec2:Modify*",
      "iam:Create*", "iam:Delete*", "iam:Update*", "iam:Attach*", "iam:Detach*",
      "dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:UpdateItem",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "auditor" {
  name   = "${var.prefix}-auditor-policy"
  policy = data.aws_iam_policy_document.auditor.json
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "auditor" {
  role       = aws_iam_role.auditor.name
  policy_arn = aws_iam_policy.auditor.arn
}

########################################
# SHARED: Assume role trust policies
########################################

# Human users — basic assume (used by developer + auditor)
data "aws_iam_policy_document" "assume_human" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.human_principal_arns
    }
  }
}

# Admin assume — requires MFA
data "aws_iam_policy_document" "assume_human_mfa" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.human_principal_arns
    }
    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }
  }
}
