output "warehouse_ids" {
  description = "Databricks SQL warehouse IDs keyed by warehouse name."
  value       = { for name, warehouse in databricks_sql_endpoint.this : name => warehouse.id }
}

output "jdbc_urls" {
  description = "JDBC connection URLs keyed by warehouse name."
  value       = { for name, warehouse in databricks_sql_endpoint.this : name => warehouse.jdbc_url }
}
