output "group_ids" {
  description = "Group ids."
  value       = module.workspace_bootstrap.group_ids
}




output "instance_profile_ids" {
  description = "Instance profile ids."
  value       = module.instance_profiles.instance_profile_ids
}

output "metastore_id" {
  description = "Metastore id."
  value       = var.read_data_access_state ? data.terraform_remote_state.data_access[0].outputs.metastore_id : null
}

output "catalog_ids" {
  description = "Catalog ids."
  value       = var.read_data_access_state ? data.terraform_remote_state.data_access[0].outputs.catalog_ids : {}
}

output "external_location_ids" {
  description = "External location ids."
  value       = var.read_data_access_state ? data.terraform_remote_state.data_access[0].outputs.external_location_ids : {}
}

output "cluster_policy_ids" {
  description = "Cluster policy ids."
  value       = module.cluster_policies.cluster_policy_ids
}

output "warehouse_ids" {
  description = "Warehouse ids."
  value       = module.sql_warehouses.warehouse_ids
}

output "job_ids" {
  description = "Job ids."
  value       = module.job.job_ids
}
output "hello_world_init_script_path" {
  description = "Hello-world init script uploaded by the compute-policy module."
  value       = module.cluster_policies.hello_world_init_script_path
}

output "target_identity" {
  description = "Verified runtime identity for generated persona compute; null for legacy callers."
  value       = var.compute_identity
}

output "compute_group_ids" {
  description = "Existing root 02 account group IDs bound to generated persona compute."
  value       = var.compute_group_ids
}
