mock_provider "databricks" {
  alias = "accounts"
}

variables {
  name                  = "dev-monthly"
  workspace_ids         = [12345]
  alert_email_addresses = ["platform@example.com", "owner@example.com"]
}

run "default_ten_dollar_workspace_budget" {
  command = plan
  assert {
    condition     = toset([for alert in databricks_budget.this.alert_configurations : alert.quantity_threshold]) == toset(["5", "8", "10"])
    error_message = "The default budget must alert at 5, 8, and 10 USD."
  }
  assert {
    condition     = alltrue([for alert in databricks_budget.this.alert_configurations : alert.time_period == "MONTH" && alert.quantity_type == "LIST_PRICE_DOLLARS_USD" && alert.trigger_type == "CUMULATIVE_SPENDING_EXCEEDED" && toset([for action in alert.action_configurations : action.target]) == var.alert_email_addresses && alltrue([for action in alert.action_configurations : action.action_type == "EMAIL_NOTIFICATION"])])
    error_message = "Every monthly list-price threshold must email all configured recipients."
  }
  assert {
    condition     = length(databricks_budget.this.filter) == 1 && toset([for id in databricks_budget.this.filter[0].workspace_id[0].values : tonumber(id)]) == toset([12345])
    error_message = "The workspace budget must filter to the specified workspace."
  }
}

run "overrides_amount_and_tracks_whole_account" {
  command = plan
  variables {
    monthly_limit_usd           = 20
    workspace_ids               = []
    alert_threshold_percentages = [25, 100]
  }
  assert {
    condition     = toset([for alert in databricks_budget.this.alert_configurations : alert.quantity_threshold]) == toset(["5", "20"]) && length(databricks_budget.this.filter) == 0
    error_message = "Overrides must change the alerts and empty workspace IDs must omit the filter."
  }
}

run "rejects_zero_budget" {
  command = plan
  variables { monthly_limit_usd = 0 }
  expect_failures = [var.monthly_limit_usd]
}

run "rejects_empty_recipients" {
  command = plan
  variables { alert_email_addresses = [] }
  expect_failures = [var.alert_email_addresses]
}

run "rejects_invalid_email" {
  command = plan
  variables { alert_email_addresses = ["invalid"] }
  expect_failures = [var.alert_email_addresses]
}

run "rejects_five_thresholds" {
  command = plan
  variables { alert_threshold_percentages = [10, 20, 50, 80, 100] }
  expect_failures = [var.alert_threshold_percentages]
}

run "rejects_zero_threshold" {
  command = plan
  variables { alert_threshold_percentages = [0, 100] }
  expect_failures = [var.alert_threshold_percentages]
}

run "rejects_fractional_workspace_id" {
  command = plan
  variables { workspace_ids = [1.5] }
  expect_failures = [var.workspace_ids]
}

run "rejects_blank_name" {
  command = plan
  variables { name = " " }
  expect_failures = [var.name]
}
