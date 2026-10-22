output "cross_account_role_arn" {
  description = "ARN for the Databricks credential configuration."
  value       = aws_iam_role.databricks_cross_account.arn
}

output "cross_account_role_name" {
  description = "Name of the Databricks cross-account role."
  value       = aws_iam_role.databricks_cross_account.name
}

output "workspace_instance_profile_arn" {
  description = "ARN of the EC2 instance profile for Databricks compute."
  value       = aws_iam_instance_profile.workspace.arn
}

output "workspace_instance_profile_role_arn" {
  description = "ARN of the EC2 role. The root storage module attaches its S3 policy to this role."
  value       = aws_iam_role.workspace_instance_profile.arn
}

output "workspace_instance_profile_role_name" {
  description = "Name of the EC2 role. The root storage module attaches its S3 policy to this role."
  value       = aws_iam_role.workspace_instance_profile.name
}
