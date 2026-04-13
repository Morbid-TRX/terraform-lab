output "developer_role_arn" {
  description = "ARN of the Developer IAM role"
  value       = aws_iam_role.developer.arn
}

output "cicd_role_arn" {
  description = "ARN of the CI/CD IAM role (assumed via GitHub Actions OIDC)"
  value       = aws_iam_role.cicd.arn
}

output "admin_role_arn" {
  description = "ARN of the Admin IAM role (MFA required)"
  value       = aws_iam_role.admin.arn
}

output "auditor_role_arn" {
  description = "ARN of the Auditor IAM role (read-only)"
  value       = aws_iam_role.auditor.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
