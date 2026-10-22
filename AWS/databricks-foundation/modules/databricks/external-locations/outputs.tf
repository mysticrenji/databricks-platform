output "external_location_ids" {
  description = "Unity Catalog external location IDs keyed by location name."
  value       = { for name, location in databricks_external_location.this : name => location.id }
}

output "external_location_urls" {
  description = "Registered S3 URLs keyed by external location name."
  value       = { for name, location in databricks_external_location.this : name => location.url }
}
