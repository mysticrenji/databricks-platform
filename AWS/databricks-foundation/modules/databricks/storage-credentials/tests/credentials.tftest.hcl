mock_provider "databricks" {
  alias = "workspace"
}
variables {
  credentials = {
    landing = {
      name     = "dev-landing"
      role_arn = "arn:aws:iam::123456789012:role/dev-landing"
    }
  }
}
run "credentials_are_isolated_without_validation_bypass" {
  command = plan
  assert {
    condition     = !databricks_storage_credential.this["landing"].skip_validation && databricks_storage_credential.this["landing"].isolation_mode == "ISOLATION_MODE_ISOLATED"
    error_message = "Storage credentials must be isolated and must not bypass validation."
  }
}
