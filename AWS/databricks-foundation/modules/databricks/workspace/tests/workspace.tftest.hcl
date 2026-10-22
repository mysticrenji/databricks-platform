mock_provider "databricks" {
  alias = "accounts"
}

variables {
  databricks_account_id    = "12345678-1234-1234-1234-123456789abc"
  workspace_name           = "analytics-dev"
  aws_region               = "eu-central-1"
  credentials_id           = "credentials-123"
  storage_configuration_id = "storage-123"
  network_id               = "network-123"
}

run "creates_workspace_from_account_configuration" {
  command = plan

  assert {
    condition     = databricks_mws_workspaces.this.workspace_name == "analytics-dev"
    error_message = "The workspace must use the configured name."
  }

  assert {
    condition     = databricks_mws_workspaces.this.aws_region == "eu-central-1"
    error_message = "The workspace must use the configured AWS Region."
  }

  assert {
    condition     = databricks_mws_workspaces.this.credentials_id == "credentials-123" && databricks_mws_workspaces.this.storage_configuration_id == "storage-123" && databricks_mws_workspaces.this.network_id == "network-123"
    error_message = "The workspace must consume all account configuration IDs."
  }

  assert {
    condition     = databricks_mws_workspaces.this.pricing_tier == "PREMIUM"
    error_message = "The default workspace tier must be PREMIUM."
  }
}

run "allows_enterprise_tier" {
  command = plan

  variables {
    pricing_tier = "ENTERPRISE"
  }

  assert {
    condition     = databricks_mws_workspaces.this.pricing_tier == "ENTERPRISE"
    error_message = "The module must allow the ENTERPRISE tier."
  }
}

run "rejects_unsupported_pricing_tier" {
  command = plan

  variables {
    pricing_tier = "STANDARD"
  }

  expect_failures = [var.pricing_tier]
}
