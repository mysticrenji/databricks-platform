output "uc_storage_role_arns" {
  description = "Dedicated UC IAM roles by purpose."
  value       = module.data_access.role_arns
}
output "storage_credential_names" {
  description = "Unity Catalog credential names by purpose."
  value       = module.data_access.credential_names
}
output "external_location_ids" {
  description = "Validated external locations."
  value       = merge(module.external_locations.external_location_ids, module.data_access.external_location_ids)
}
output "catalog_ids" {
  description = "Optional learning catalog IDs."
  value       = merge(module.catalogs.catalog_ids, module.data_access.catalog_ids)
}

output "cluster_log_volume_path" {
  description = "Cluster logging volume path; use in 04-workspace after this root is applied."
  value       = module.data_access.cluster_log_volume_path
}
output "init_scripts_volume_path" {
  description = "Existing volume for init-script uploads by 04-workspace."
  value       = module.data_access.init_scripts_volume_path
}

output "metastore_id" {
  description = "Created or explicitly assigned regional metastore ID; empty when using an unmanaged existing assignment."
  value       = var.create_metastore ? module.unity_catalog_metastore["dev"].metastore_id : var.existing_metastore_id
}
