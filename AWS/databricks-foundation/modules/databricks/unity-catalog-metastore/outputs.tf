output "metastore_id" {
  description = "Unity Catalog metastore ID for storage credentials, catalogs, and grants."
  value       = databricks_metastore.this.id
}

output "metastore_assignment_id" {
  description = "Databricks metastore assignment ID for the workspace."
  value       = databricks_metastore_assignment.workspace.id
}

output "metastore_storage_root" {
  description = "Configured metastore-level managed storage root, or null when catalog-level managed locations are used."
  value       = databricks_metastore.this.storage_root
}
