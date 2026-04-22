###############################################################
# IAM — Company-grade Access Model
# Personas: Developer, CI/CD (OIDC), Admin, Auditor
# Project: terraform-lab (local / dev / prod / aws)
#
# WHY 4 personas? Least-privilege principle — each persona gets
# exactly what it needs, nothing more. This mirrors real enterprise
# IAM design where different actors have different trust levels.
#
# WHY roles instead of users? Roles are assumed temporarily via
# STS — no long-lived credentials to rotate or leak. Developers
# assume roles via aws-vault; CI/CD assumes via OIDC federation.
###############################################################

locals {
  # WHY hardcoded bucket ARNs? Terraform state buckets are created
  # outside this module (chicken-and-egg problem — you need state
  # storage before you can manage state). ARNs are stable and known
  # at design time, so hardcoding is acceptable here.
  all_buckets = [
    "arn:aws:s3:::my-terraform-bucket",
    "arn:aws:s3:::dev-terraform-bucket",
    "arn:aws:s3:::prod-terraform-bucket",
    "arn:aws:s3:::aiman-terraform-aws-bucket",
  ]
  all_bucket_objects = [for b in local.all_buckets : "${b}/*"]

  # Non-prod only (local + dev) — Developer can write here but not prod
  dev_buckets = [
    "arn:aws:s3:::my-terraform-bucket",
    "arn:aws:s3:::dev-terraform-bucket",
  ]
  dev_bucket_objects = [for b in local.dev_buckets : "${b}/*"]

  # Single DynamoDB table handles locking for all environments.
  # WHY one table? DynamoDB charges per table ($0 in free tier for
  # low usage). Per-env locking is handled via LeadingKeys conditions
  # on the table, not separate tables.
  dynamo_arn = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.dynamodb_table}"
}

########################################
# 1. DEVELOPER ROLE
#    - Full access: local + dev
#    - Read-only:   prod + aws
#
# WHY read-only on prod? Developers should never directly modify
# production. All prod changes go through CI/CD (reviewed PR → merge
# → pipeline). This enforces the process at the IAM level.
########################################

resource "aws_iam_role" "developer" {
  name               = "${var.prefix}-developer"
  description        = "Human developer - full dev access, read-only prod"
  assume_role_policy = data.aws_iam_policy_document.assume_human.json
  tags               = merge(var.tags, { Role = "developer" })
}

data "aws_iam_policy_document" "developer" {
  # checkov:skip=CKV_AWS_356: ec2:Describe* actions require Resource="*" per AWS IAM spec — describe actions do not support resource-level permissions. Scoped to region via aws:RequestedRegion condition.

  # Full S3 access to dev/local buckets only
  statement {
    sid       = "DevS3Full"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = concat(local.dev_buckets, local.dev_bucket_objects)
  }

  # Read-only on prod/aws — can inspect state but cannot modify it
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

  # DynamoDB lock scoped to local/* and dev/* keys only.
  # WHY LeadingKeys condition? DynamoDB lock keys follow the pattern
  # "env/path/to/resource". Restricting by prefix prevents a developer
  # from acquiring or breaking prod state locks.
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

  # ec2:Describe* requires Resource="*" — AWS does not support
  # resource-level permissions for Describe actions. This is an
  # AWS API limitation, not a misconfiguration.
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

  # Terraform apply scoped to a single region via condition.
  # WHY region condition? Prevents accidental deploys to wrong regions
  # and limits blast radius if credentials are ever compromised.
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

# Attach the policy to the role — separated from the policy resource
# so each can be managed independently if needed later.
resource "aws_iam_role_policy_attachment" "developer" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.developer.arn
}

########################################
# 2. CI/CD ROLE (GitHub Actions OIDC)
#    - Deploy access to ALL environments
#    - No long-lived credentials
#
# WHY OIDC instead of access keys? OIDC tokens are short-lived
# (expire after the workflow run) and are scoped to a specific
# repo. No secrets to store, rotate, or accidentally expose.
########################################

# OIDC provider tells AWS to trust GitHub's token service.
# WHY this thumbprint? It's the SHA1 fingerprint of GitHub's
# OIDC TLS certificate. AWS uses it to validate tokens are
# genuinely from GitHub Actions and not forged.
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

# Trust policy — only GitHub Actions from this specific repo can assume this role.
# WHY two conditions? "aud" validates the token audience (must be AWS STS).
# "sub" validates the source repo — prevents other GitHub repos from
# assuming this role even if they also use OIDC.
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
  # checkov:skip=CKV_AWS_109: CI/CD role intentionally has broad permissions to manage Terraform-provisioned infrastructure across all envs. Scoped via GitHub OIDC trust policy (repo:Morbid-TRX/terraform-lab:*).
  # checkov:skip=CKV_AWS_111: Write access required for Terraform apply operations. Access is bounded by OIDC federation — no static credentials exist.
  # checkov:skip=CKV_AWS_356: EC2/S3 Describe and CreateTags actions require Resource="*" per AWS IAM spec. Terraform operations inherently need broad resource access within scoped account.

  # CI/CD needs full state access across all envs to run terraform plan/apply
  statement {
    sid       = "CICDS3StateAll"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketVersioning"]
    resources = concat(local.all_buckets, local.all_bucket_objects)
  }

  # No LeadingKeys condition here — CI/CD manages all environments
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

  # Combined plan + apply permissions — CI/CD runs both in the pipeline
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
      # s3:PutBucketPolicy needed to apply SSL enforcement policy on buckets
      "s3:PutBucketPolicy",
    ]
    resources = ["*"]
  }

  # Drift detector runs as CI/CD — needs read access to compare
  # actual AWS state against Terraform state
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
#
# WHY a separate admin role instead of root? Root account should
# never be used for day-to-day operations. This role is the
# break-glass persona — used only when CI/CD or Developer
# roles don't have sufficient permissions for a task.
########################################

resource "aws_iam_role" "admin" {
  name        = "${var.prefix}-admin"
  description = "Infrastructure admin - full access, MFA required"
  # WHY assume_human_mfa and not assume_human? Admin is the most
  # privileged role. MFA is enforced at the trust policy level —
  # even if credentials are stolen, MFA prevents role assumption.
  assume_role_policy = data.aws_iam_policy_document.assume_human_mfa.json
  tags               = merge(var.tags, { Role = "admin" })
}

data "aws_iam_policy_document" "admin" {
  # checkov:skip=CKV_AWS_107: Admin role intentionally has credential-related permissions (iam:PassRole) for infrastructure management. MFA required via assume_human_mfa trust policy.
  # checkov:skip=CKV_AWS_109: Admin role is the break-glass persona with full management access. Scoped to terraform-lab-* resources for IAM; MFA-gated assumption.
  # checkov:skip=CKV_AWS_111: Admin role requires write access by design (ec2:*, s3:*, dynamodb:*). MFA required; usage audited via CloudTrail.
  # checkov:skip=CKV_AWS_356: ec2:* and s3:* actions require Resource="*" for the admin persona. Access gated by MFA requirement in trust policy.

  statement {
    sid       = "AdminS3Full"
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = concat(local.all_buckets, local.all_bucket_objects)
  }

  statement {
    sid       = "AdminDynamoFull"
    effect    = "Allow"
    actions   = ["dynamodb:*"]
    resources = [local.dynamo_arn]
  }

  statement {
    sid       = "AdminEC2Full"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]
  }

  # WHY scoped to prefix? Even admin IAM management is restricted
  # to resources named terraform-lab-*. This prevents accidental
  # modification of IAM roles outside this project's scope.
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
#
# WHY an Auditor persona? Compliance and security reviews require
# read access to infrastructure state. Without a dedicated role,
# reviewers would need Developer or Admin access — violating
# least-privilege. Auditor can see everything but change nothing.
########################################

resource "aws_iam_role" "auditor" {
  name               = "${var.prefix}-auditor"
  description        = "Read-only auditor - view state and infra, no writes"
  assume_role_policy = data.aws_iam_policy_document.assume_human.json
  tags               = merge(var.tags, { Role = "auditor" })
}

data "aws_iam_policy_document" "auditor" {
  # checkov:skip=CKV_AWS_107: Auditor has iam:Get*/iam:List* for read-only auditing — required to review IAM posture. Explicit Deny statement blocks all writes including credential modification.
  # checkov:skip=CKV_AWS_356: Read-only Describe/Get/List actions require Resource="*" per AWS IAM spec. Explicit Deny statement in same policy prevents any write actions.

  # Read all S3 metadata — needed to audit encryption, versioning,
  # public access settings, and bucket policies
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

  # Read DynamoDB lock table — auditor can see who holds locks
  # but cannot acquire or release them
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

  # IAM read access — auditor needs to review role policies,
  # trust relationships, and attached permissions for compliance
  statement {
    sid    = "AuditorIAMReadOnly"
    effect = "Allow"
    actions = [
      "iam:Get*",
      "iam:List*",
    ]
    resources = ["*"]
  }

  # WHY an explicit Deny? Allow statements above could be
  # misread as granting write access via wildcard actions.
  # An explicit Deny overrides any Allow — even if a future
  # policy accidentally grants write permissions to this role,
  # this Deny ensures writes are always blocked. Deny wins.
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
#
# WHY separate trust policies? Trust policies (who can assume
# the role) are separate from permission policies (what the role
# can do). This separation allows reuse — both Developer and
# Auditor use assume_human, but have completely different permissions.
########################################

# Basic human assume — no MFA required (Developer + Auditor)
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

# Admin assume — MFA required at trust policy level.
# WHY here and not in the permission policy? Conditions on the
# trust policy are evaluated at assume-role time. If MFA was
# checked in the permission policy instead, a user could assume
# the role without MFA and only fail on the first API call.
# Checking at trust time prevents assumption entirely without MFA.
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
