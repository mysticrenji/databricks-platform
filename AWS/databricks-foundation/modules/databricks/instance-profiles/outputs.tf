output "instance_profile_ids" {
  description = "Registered Databricks instance-profile IDs keyed by input identifier."
  value       = { for key, profile in databricks_instance_profile.this : key => profile.id }
}

output "instance_profile_arns" {
  description = "Registered AWS instance-profile ARNs keyed by input identifier."
  value       = { for key, profile in databricks_instance_profile.this : key => profile.instance_profile_arn }
}
