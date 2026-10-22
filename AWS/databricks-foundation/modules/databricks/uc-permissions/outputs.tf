output "grant_ids" {
  description = "Managed per-principal grant IDs keyed by the supplied stable scope key."
  value       = { for key, grant in databricks_grant.this : key => grant.id }
}
