output "github_actions_role_arn" {
  description = "IAM role ARN for aws-actions/configure-aws-credentials."
  value       = aws_iam_role.github_actions.arn
}

output "github_actions_oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
