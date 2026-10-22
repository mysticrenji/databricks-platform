mock_provider "databricks" {
  alias = "workspace"
}

variables {
  external_locations = {
    raw_data = {
      url             = "s3://company-data-dev/raw"
      credential_name = "company-data-dev"
      read_only       = true
      grants = {
        "data-engineers" = ["READ_FILES", "CREATE_EXTERNAL_TABLE"]
        "data-analysts"  = ["READ_FILES"]
      }
    }
  }
}

run "creates_location_with_explicit_grants" {
  command = plan

  assert {
    condition     = databricks_external_location.this["raw_data"].url == "s3://company-data-dev/raw" && databricks_external_location.this["raw_data"].credential_name == "company-data-dev"
    error_message = "The external location must use the configured S3 path and storage credential."
  }

  assert {
    condition     = databricks_external_location.this["raw_data"].read_only && !databricks_external_location.this["raw_data"].skip_validation
    error_message = "The location must preserve read-only access and validation settings."
  }

  assert {
    condition     = length(databricks_grants.external_location["raw_data"].grant) == 2
    error_message = "The external location must manage both requested principal grants."
  }
}

run "registers_location_without_delegating_access" {
  command = plan

  variables {
    external_locations = {
      landing = {
        url             = "s3://company-data-dev/landing"
        credential_name = "company-data-dev"
      }
    }
  }

  assert {
    condition     = length(databricks_grants.external_location) == 0
    error_message = "No grants must be created unless explicitly configured."
  }
}

run "rejects_duplicate_urls" {
  command = plan

  variables {
    external_locations = {
      raw_a = {
        url             = "s3://company-data-dev/raw"
        credential_name = "company-data-dev"
      }
      raw_b = {
        url             = "s3://company-data-dev/raw"
        credential_name = "company-data-dev"
      }
    }
  }

  expect_failures = [var.external_locations]
}
