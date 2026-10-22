output "role_arns" {
  description = "Created UC storage IAM role ARNs by bucket purpose."
  value       = { for key, role in module.uc_storage_roles.roles : key => role.arn }
}

output "credential_names" {
  description = "Unity Catalog storage credential names by purpose."
  value       = module.storage_credentials.names
}

output "external_location_ids" {
  description = "Validated external-location IDs."
  value       = module.external_locations.external_location_ids
}

output "catalog_ids" {
  description = "Optional analytics and operations catalog IDs."
  value       = merge(module.catalogs.catalog_ids, module.observability_catalog.catalog_ids)
}

output "cluster_log_volume_path" {
  description = "Created managed volume path for compute logs, or null when disabled."
  value = var.observability == null ? null : module.observability_catalog.volume_paths[
    "${var.observability.catalog_name}.${var.observability.schema_name}.${var.observability.volume_name}"
  ]
}
output "init_scripts_volume_path" {
  description = "Operations init-scripts volume path, or null when disabled. File uploads are owned by cluster-policies."
  value       = var.enable_init_scripts_volume && var.observability != null ? "/Volumes/${var.observability.catalog_name}/${var.observability.schema_name}/init_scripts" : null
  depends_on  = [module.observability_catalog]
}
