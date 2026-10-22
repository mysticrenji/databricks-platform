output "budget_id" {
  description = "Databricks budget configuration ID."
  value       = databricks_budget.this.budget_configuration_id
}

output "alert_thresholds_usd" {
  description = "Monthly USD alert thresholds calculated from the budget and percentages."
  value       = toset([for percent in var.alert_threshold_percentages : var.monthly_limit_usd * percent / 100])
}
