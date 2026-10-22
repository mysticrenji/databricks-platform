output "target_identity" {
  description = "Verified provisioning identity bound to these workspace entitlements."
  value = {
    environment   = var.environment_name
    workspace     = var.workspace_key
    account_id    = var.account_id
    workspace_id  = tostring(var.workspace_id)
    workspace_url = var.workspace_url
  }
}
output "group_ids" {
  description = "Existing account group IDs keyed by stable persona."
  value       = module.workspace_entitlements.group_ids
}
output "entitlement_ids" {
  description = "Workspace entitlement resource IDs keyed by stable persona."
  value       = module.workspace_entitlements.entitlement_ids
}
