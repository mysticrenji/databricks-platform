output "group_ids" {
  description = "Workspace-local group IDs keyed by display name."
  value       = { for name, group in databricks_group.this : name => group.id }
}

output "service_principal_ids" {
  description = "Workspace-local service principal IDs keyed by display name."
  value       = { for name, service_principal in databricks_service_principal.this : name => service_principal.id }
}

output "service_principal_application_ids" {
  description = "Workspace-local service principal application IDs keyed by display name."
  value       = { for name, service_principal in databricks_service_principal.this : name => service_principal.application_id }
}
