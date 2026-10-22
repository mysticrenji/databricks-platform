output "cluster_policy_ids" {
  description = "Databricks cluster policy IDs keyed by policy name."
  value       = { for name, policy in databricks_cluster_policy.this : name => policy.id }
}
output "hello_world_init_script_path" {
  description = "Uploaded demo init-script path, or null when uploading is disabled."
  value       = try(databricks_file.hello_world_init_script["hello"].path, null)
}
