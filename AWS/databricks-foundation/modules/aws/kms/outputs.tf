output "enabled" {
  description = "Whether a customer-managed KMS key was created."
  value       = var.enabled
}

output "key_arn" {
  description = "KMS key ARN when enabled; otherwise null. Pass this to root-storage.kms_key_arn."
  value       = try(aws_kms_key.workspace[0].arn, null)
}

output "key_id" {
  description = "KMS key ID when enabled; otherwise null."
  value       = try(aws_kms_key.workspace[0].key_id, null)
}

output "alias_name" {
  description = "KMS alias name when enabled; otherwise null."
  value       = try(aws_kms_alias.workspace[0].name, null)
}
