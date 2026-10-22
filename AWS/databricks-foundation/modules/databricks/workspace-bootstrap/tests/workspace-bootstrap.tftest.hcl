mock_provider "databricks" {
  alias = "workspace"
}

variables {
  groups = {
    "data-analysts" = {
      databricks_sql_access = true
    }
    "data-engineers" = {
      allow_cluster_create = true
    }
  }

  service_principals = {
    "ci-deployments" = {
      allow_cluster_create = true
    }
  }
}

run "creates_least_privilege_workspace_identities" {
  command = plan

  assert {
    condition     = databricks_group.this["data-analysts"].workspace_access && databricks_group.this["data-analysts"].databricks_sql_access && !databricks_group.this["data-analysts"].allow_cluster_create
    error_message = "Analysts must receive workspace and SQL access without cluster creation."
  }

  assert {
    condition     = databricks_group.this["data-engineers"].workspace_access && databricks_group.this["data-engineers"].allow_cluster_create && !databricks_group.this["data-engineers"].databricks_sql_access
    error_message = "Engineers must receive only the requested cluster entitlement."
  }

  assert {
    condition     = databricks_service_principal.this["ci-deployments"].active && databricks_service_principal.this["ci-deployments"].workspace_access && databricks_service_principal.this["ci-deployments"].allow_cluster_create
    error_message = "Automation principals must be active and receive their requested entitlement."
  }
}

run "creates_no_identities_by_default" {
  command = plan

  variables {
    groups             = {}
    service_principals = {}
  }

  assert {
    condition     = length(databricks_group.this) == 0 && length(databricks_service_principal.this) == 0
    error_message = "The module must not create identities unless explicitly requested."
  }
}

run "rejects_blank_group_names" {
  command = plan

  variables {
    groups = {
      " invalid " = {}
    }
  }

  expect_failures = [var.groups]
}
