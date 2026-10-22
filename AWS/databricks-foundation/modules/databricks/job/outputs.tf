output "job_ids" {
  description = "Databricks job IDs keyed by job name."
  value       = { for name, job in databricks_job.this : name => job.id }
}

output "job_urls" {
  description = "Databricks job URLs keyed by job name."
  value       = { for name, job in databricks_job.this : name => job.url }
}
