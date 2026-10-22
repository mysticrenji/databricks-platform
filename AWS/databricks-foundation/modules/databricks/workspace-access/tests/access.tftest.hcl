mock_provider "databricks" {
  alias = "accounts"
  mock_resource "databricks_group" { defaults = { id = "500" } }
  mock_data "databricks_group" { defaults = { id = "700" } }
}
mock_provider "databricks" { alias = "workspace" }

variables {
  workspace_id = 123
  groups = {
    engineers = {
      display_name = "dev-demo-engineers", lifecycle = "create", workspace_role = "USER"
      entitlements = { workspace_access = true, databricks_sql_access = true }
    }
    analysts = {
      display_name = "dev-demo-analysts", lifecycle = "external", account_group_id = "700", workspace_role = "USER"
      entitlements = { workspace_access = true, databricks_sql_access = true }
    }
  }
}

run "creates_and_references_account_groups_without_membership" {
  command = apply
  assert {
    condition     = output.group_ids == { engineers = "500", analysts = "700" }
    error_message = "Created and external group IDs must remain distinct and correctly keyed."
  }
  assert {
    condition     = databricks_mws_permission_assignment.external["analysts"].workspace_id == 123 && databricks_entitlements.this["engineers"].group_id == "500" && !databricks_entitlements.this["engineers"].allow_cluster_create
    error_message = "Assignments and bounded workspace entitlements must use the registered account group."
  }
}

run "rejects_external_identity_mismatch" {
  command = plan
  variables {
    groups = {
      analysts = {
        display_name = "dev-demo-analysts", lifecycle = "external", account_group_id = "999", workspace_role = "USER"
        entitlements = { workspace_access = true, databricks_sql_access = true }
      }
    }
  }
  expect_failures = [data.databricks_group.external]
}

run "rejects_invalid_role" {
  command = plan
  variables {
    groups = {
      bad = {
        display_name = "dev-demo-bad", lifecycle = "create", workspace_role = "ACCOUNT_ADMIN"
        entitlements = { workspace_access = true, databricks_sql_access = false }
      }
    }
  }
  expect_failures = [var.groups]
}
