output "catalog_ids" {
  description = "Unity Catalog IDs keyed by catalog name."
  value       = { for name, catalog in databricks_catalog.this : name => catalog.id }
}

output "schema_ids" {
  description = "Unity Catalog schema IDs keyed by catalog.schema."
  value       = { for name, schema in databricks_schema.this : name => schema.id }
}

output "volume_ids" {
  description = "Unity Catalog volume IDs keyed by catalog.schema.volume."
  value       = { for name, volume in databricks_volume.this : name => volume.id }
}

output "volume_paths" {
  description = "Workspace volume paths keyed by catalog.schema.volume."
  value       = { for name, volume in databricks_volume.this : name => volume.volume_path }
}
