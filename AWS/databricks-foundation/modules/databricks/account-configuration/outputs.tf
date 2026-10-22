output "credentials_id" {
  description = "Databricks credential configuration ID for workspace creation."
  value       = databricks_mws_credentials.this.credentials_id
}

output "storage_configuration_id" {
  description = "Databricks root storage configuration ID for workspace creation."
  value       = databricks_mws_storage_configurations.this.storage_configuration_id
}

output "network_id" {
  description = "Databricks customer-managed network configuration ID for workspace creation."
  value       = databricks_mws_networks.this.network_id
}
