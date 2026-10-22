output "entitlement_ids" {
  description = "Entitlement resource IDs keyed by stable persona."
  value       = { for key, entitlement in databricks_entitlements.this : key => entitlement.id }
}
output "group_ids" {
  description = "Existing account group IDs keyed by stable persona."
  value       = { for key, group in var.groups : key => group.group_id }
}
