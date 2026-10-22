resource "databricks_budget" "this" {
  provider     = databricks.accounts
  display_name = var.name

  dynamic "alert_configurations" {
    for_each = var.alert_threshold_percentages
    content {
      time_period        = "MONTH"
      trigger_type       = "CUMULATIVE_SPENDING_EXCEEDED"
      quantity_type      = "LIST_PRICE_DOLLARS_USD"
      quantity_threshold = tostring(var.monthly_limit_usd * alert_configurations.value / 100)
      dynamic "action_configurations" {
        for_each = var.alert_email_addresses
        content {
          action_type = "EMAIL_NOTIFICATION"
          target      = action_configurations.value
        }
      }
    }
  }

  dynamic "filter" {
    for_each = length(var.workspace_ids) > 0 ? [var.workspace_ids] : []
    content {
      workspace_id {
        operator = "IN"
        values   = sort([for id in filter.value : tostring(id)])
      }
    }
  }
}
