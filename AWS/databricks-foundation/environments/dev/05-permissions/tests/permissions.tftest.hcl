mock_provider "databricks" {
  alias = "accounts"
  mock_resource "databricks_group" { defaults = { id = "500" } }
  mock_data "databricks_group" { defaults = { id = "500" } }
}
mock_provider "databricks" { alias = "workspace" }
variables {
  account_id    = "11111111-1111-1111-1111-111111111111"
  workspace_id  = 123
  workspace_url = "https://dbc-example.cloud.databricks.com"
  metastore_id  = "22222222-2222-2222-2222-222222222222"
  groups = {
    engineers = {
      display_name = "dev-demo-engineers", lifecycle = "create", workspace_role = "USER"
      entitlements = { workspace_access = true, databricks_sql_access = true }
    }
  }
  grants = {
    bronze = { object_type = "schema", object_name = "dev_demo.bronze", group_key = "engineers", privileges = ["USE_SCHEMA", "SELECT"] }
  }
}
run "permission_root_identity_and_group_wiring" {
  command = apply
  assert {
    condition     = output.group_ids["engineers"] == "500" && output.target_identity.workspace_id == "123"
    error_message = "The permissions root must bind account groups to the selected existing workspace."
  }
}

run "bootstrap_groups_are_referenced_without_workspace_access_management" {
  command = apply
  variables {
    groups = {
      engineers = {
        display_name = "dev-demo-engineers", lifecycle = "terraform", account_group_id = "500", workspace_role = "USER"
        entitlements = { workspace_access = true, databricks_sql_access = true }
      }
    }
  }
  assert {
    condition     = output.group_ids["engineers"] == "500" && length(data.databricks_group.bootstrap) == 1 && length(module.workspace_access.group_ids) == 0
    error_message = "Root 05 must reference the verified root 02 group without managing its workspace access."
  }
}

run "rejects_changed_bootstrap_group_identity" {
  command = plan
  variables {
    groups = {
      engineers = {
        display_name = "dev-demo-engineers", lifecycle = "terraform", account_group_id = "999", workspace_role = "USER"
        entitlements = { workspace_access = true, databricks_sql_access = true }
      }
    }
  }
  expect_failures = [data.databricks_group.bootstrap]
}
