output "workspace_id" {
  description = "Databricks workspace ID for account assignments and workspace-level configuration."
  value       = databricks_mws_workspaces.this.workspace_id
}

output "workspace_url" {
  description = "Databricks workspace URL for configuring a workspace-level provider."
  value       = databricks_mws_workspaces.this.workspace_url
}
