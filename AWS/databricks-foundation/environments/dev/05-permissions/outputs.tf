output "target_identity" {
  description = "Identity binding used to reject retargeting an existing permissions state."
  value       = { account_id = var.account_id, workspace_id = tostring(var.workspace_id), workspace_url = var.workspace_url, metastore_id = var.metastore_id }
}
output "group_ids" {
  description = "Managed or explicitly referenced account group SCIM IDs."
  value       = local.group_ids
}

output "grant_ids" {
  description = "Managed group/object grant IDs keyed by stable scope identity."
  value       = module.uc_permissions.grant_ids
}
