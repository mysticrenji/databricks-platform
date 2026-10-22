mock_provider "databricks" {
  alias = "workspace"
}

variables {
  warehouses = {
    "analytics-bi" = {
      cluster_size              = "Small"
      auto_stop_mins            = 10
      min_num_clusters          = 1
      max_num_clusters          = 2
      enable_serverless_compute = true
      tags = {
        environment = "dev"
      }
      permissions = {
        groups = {
          "data-analysts" = "CAN_USE"
        }
      }
    }
  }
}

run "creates_bounded_warehouse_with_explicit_access" {
  command = plan

  assert {
    condition     = databricks_sql_endpoint.this["analytics-bi"].cluster_size == "Small" && databricks_sql_endpoint.this["analytics-bi"].auto_stop_mins == 10
    error_message = "The warehouse must use its configured size and auto-stop period."
  }

  assert {
    condition     = databricks_sql_endpoint.this["analytics-bi"].min_num_clusters == 1 && databricks_sql_endpoint.this["analytics-bi"].max_num_clusters == 2 && databricks_sql_endpoint.this["analytics-bi"].enable_serverless_compute
    error_message = "The warehouse must preserve its bounded capacity and serverless setting."
  }

  assert {
    condition     = length(databricks_permissions.warehouse["analytics-bi"].access_control) == 1
    error_message = "The configured group permission must be managed."
  }
}

run "creates_no_warehouses_by_default" {
  command = plan

  variables {
    warehouses = {}
  }

  assert {
    condition     = length(databricks_sql_endpoint.this) == 0 && length(databricks_permissions.warehouse) == 0
    error_message = "The module must not create warehouses unless explicitly configured."
  }
}

run "rejects_invalid_capacity_range" {
  command = plan

  variables {
    warehouses = {
      invalid = {
        min_num_clusters = 3
        max_num_clusters = 1
      }
    }
  }

  expect_failures = [terraform_data.validation]
}
