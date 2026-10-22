mock_provider "databricks" { alias = "workspace" }
variables {
  grants = {
    bronze = { object_type = "schema", object_name = "dev_demo.bronze", principal = "dev-demo-engineers", privileges = ["USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"] }
    sales  = { object_type = "table", object_name = "dev_demo.gold.sales_summary", principal = "dev-demo-engineers", privileges = ["SELECT"] }
  }
}

run "only_grants_on_existing_objects" {
  command = apply
  assert {
    condition     = databricks_grant.this["bronze"].schema == "dev_demo.bronze" && databricks_grant.this["sales"].table == "dev_demo.gold.sales_summary" && databricks_grant.this["sales"].principal == "dev-demo-engineers"
    error_message = "Grant scopes must preserve existing schema/table names and the requesting group."
  }
  assert {
    condition     = toset(databricks_grant.this["sales"].privileges) == toset(["SELECT"])
    error_message = "Table reader access must not acquire writer or ownership privileges."
  }
}

run "rejects_ownership" {
  command = plan
  variables {
    grants = { bad = { object_type = "catalog", object_name = "dev_demo", principal = "dev-demo-engineers", privileges = ["ALL_PRIVILEGES"] } }
  }
  expect_failures = [var.grants]
}

run "rejects_duplicate_principal_scope" {
  command = plan
  variables {
    grants = {
      first  = { object_type = "schema", object_name = "dev_demo.bronze", principal = "dev-demo-engineers", privileges = ["SELECT"] }
      second = { object_type = "schema", object_name = "dev_demo.bronze", principal = "dev-demo-engineers", privileges = ["MODIFY"] }
    }
  }
  expect_failures = [var.grants]
}
