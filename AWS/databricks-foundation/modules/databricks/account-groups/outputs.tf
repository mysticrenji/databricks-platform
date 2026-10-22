output "group_ids" {
  description = "Account SCIM group IDs keyed by display name."
  value       = { for name, group in databricks_group.this : name => group.id }
}

output "workspace_assignment_ids" {
  description = "Workspace assignment IDs keyed by group display name."
  value       = { for name, assignment in databricks_mws_permission_assignment.this : name => assignment.id }
}
