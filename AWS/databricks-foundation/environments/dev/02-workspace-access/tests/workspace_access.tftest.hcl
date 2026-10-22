mock_provider "databricks" { alias = "workspace" }
variables {
  environment_name = "dev"
  workspace_key    = "demo"
  account_id       = "11111111-1111-1111-1111-111111111111"
  workspace_id     = 123
  workspace_url    = "https://dbc-example.cloud.databricks.com"
  groups = {
    analysts = { group_id = "102", workspace_role = "USER", workspace_access = false, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false }
  }
}
run "binds_verified_provisioning_identity" {
  command = apply
  assert {
    condition     = output.target_identity == { environment = "dev", workspace = "demo", account_id = "11111111-1111-1111-1111-111111111111", workspace_id = "123", workspace_url = "https://dbc-example.cloud.databricks.com" } && output.group_ids == { analysts = "102" } && length(output.entitlement_ids) == 1
    error_message = "The workspace-only root must preserve the verified provisioning target and existing group identity."
  }
}

run "rejects_other_environment" {
  command = plan
  variables { environment_name = "staging" }
  expect_failures = [var.environment_name]
}

run "rejects_invalid_workspace" {
  command = plan
  variables { workspace_key = "../demo" }
  expect_failures = [var.workspace_key]
}

run "rejects_invalid_account" {
  command = plan
  variables { account_id = "account" }
  expect_failures = [var.account_id]
}

run "rejects_noninteger_workspace" {
  command = plan
  variables { workspace_id = 1.5 }
  expect_failures = [var.workspace_id]
}

run "rejects_invalid_workspace_host" {
  command = plan
  variables { workspace_url = "https://accounts.cloud.databricks.com/path" }
  expect_failures = [var.workspace_url]
}

run "rejects_http_workspace_host" {
  command = plan
  variables { workspace_url = "http://dbc-example.cloud.databricks.com" }
  expect_failures = [var.workspace_url]
}
