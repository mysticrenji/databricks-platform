output "workspace_id" {
  description = "Workspace id."
  value       = module.workspace.workspace_id
}

output "workspace_url" {
  description = "Workspace url."
  value       = module.workspace.workspace_url
}

output "aws_region" {
  description = "Aws region."
  value       = data.terraform_remote_state.infra.outputs.aws_region
}

output "account_group_ids" {
  description = "Account SCIM group IDs keyed by display name."
  value       = module.account_groups.group_ids
}

output "budget_ids" {
  description = "Databricks budget IDs keyed by scope; empty when recipients are not configured."
  value       = { for key, budget in module.account_budget : key => budget.budget_id }
}
