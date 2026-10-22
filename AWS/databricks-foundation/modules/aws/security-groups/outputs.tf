output "workspace_security_group_id" {
  description = "Security group ID for Databricks network registration."
  value       = aws_security_group.workspace.id
}

output "workspace_security_group_arn" {
  description = "Security group ARN."
  value       = aws_security_group.workspace.arn
}
