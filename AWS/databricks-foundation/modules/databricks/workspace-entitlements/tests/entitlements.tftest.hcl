mock_provider "databricks" { alias = "workspace" }
variables {
  groups = {
    admins    = { group_id = "100", workspace_role = "ADMIN", workspace_access = true, databricks_sql_access = true, allow_cluster_create = true, allow_instance_pool_create = true }
    engineers = { group_id = "101", workspace_role = "USER", workspace_access = true, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false }
    analysts  = { group_id = "102", workspace_role = "USER", workspace_access = false, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false }
    ml        = { group_id = "103", workspace_role = "USER", workspace_access = true, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false }
  }
}
run "matrix_uses_existing_groups_only" {
  command = apply
  assert {
    condition     = output.group_ids == { admins = "100", engineers = "101", analysts = "102", ml = "103" } && length(output.entitlement_ids) == 4
    error_message = "The matrix must use the supplied account group IDs with stable persona keys."
  }
  assert {
    condition     = databricks_entitlements.this["admins"].allow_cluster_create && databricks_entitlements.this["admins"].allow_instance_pool_create && !databricks_entitlements.this["analysts"].workspace_access && databricks_entitlements.this["analysts"].databricks_sql_access && !databricks_entitlements.this["engineers"].allow_cluster_create && !databricks_entitlements.this["ml"].allow_instance_pool_create
    error_message = "The persona matrix must preserve admin capabilities and bound user feature access."
  }
}
run "empty_default_creates_nothing" {
  command = plan
  variables { groups = {} }
  assert {
    condition     = length(output.group_ids) == 0 && length(output.entitlement_ids) == 0
    error_message = "Empty input must not create entitlements."
  }
}

run "rejects_invalid_group_id" {
  command = plan
  variables { groups = { invalid = { group_id = "0", workspace_role = "USER", workspace_access = true, databricks_sql_access = false, allow_cluster_create = false, allow_instance_pool_create = false } } }
  expect_failures = [var.groups]
}

run "rejects_invalid_role" {
  command = plan
  variables { groups = { invalid = { group_id = "100", workspace_role = "ACCOUNT_ADMIN", workspace_access = true, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false } } }
  expect_failures = [var.groups]
}

run "rejects_user_unrestricted_cluster" {
  command = plan
  variables { groups = { invalid = { group_id = "100", workspace_role = "USER", workspace_access = true, databricks_sql_access = true, allow_cluster_create = true, allow_instance_pool_create = false } } }
  expect_failures = [var.groups]
}

run "rejects_user_unrestricted_pool" {
  command = plan
  variables { groups = { invalid = { group_id = "100", workspace_role = "USER", workspace_access = true, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = true } } }
  expect_failures = [var.groups]
}

run "rejects_user_without_features" {
  command = plan
  variables { groups = { invalid = { group_id = "100", workspace_role = "USER", workspace_access = false, databricks_sql_access = false, allow_cluster_create = false, allow_instance_pool_create = false } } }
  expect_failures = [var.groups]
}

run "rejects_admin_capability_removal" {
  command = plan
  variables { groups = { invalid = { group_id = "100", workspace_role = "ADMIN", workspace_access = true, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = true } } }
  expect_failures = [var.groups]
}

run "rejects_duplicate_groups" {
  command = plan
  variables {
    groups = {
      first  = { group_id = "100", workspace_role = "USER", workspace_access = true, databricks_sql_access = false, allow_cluster_create = false, allow_instance_pool_create = false }
      second = { group_id = "100", workspace_role = "USER", workspace_access = false, databricks_sql_access = true, allow_cluster_create = false, allow_instance_pool_create = false }
    }
  }
  expect_failures = [var.groups]
}
