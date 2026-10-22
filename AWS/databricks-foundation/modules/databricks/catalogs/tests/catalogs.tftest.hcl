mock_provider "databricks" {
  alias = "workspace"
}

variables {
  catalogs = {
    analytics = {
      owner        = "data-engineers"
      storage_root = "s3://company-data-dev/managed/analytics"
      grants = {
        "data-engineers" = ["USE_CATALOG", "CREATE_SCHEMA"]
      }
      schemas = {
        curated = {
          grants = {
            "data-engineers" = ["USE_SCHEMA", "CREATE_TABLE"]
          }
          volumes = {
            reference = {
              grants = {
                "data-engineers" = ["READ_VOLUME", "WRITE_VOLUME"]
              }
            }
            ingestion = {
              volume_type      = "EXTERNAL"
              storage_location = "s3://company-data-dev/landing/ingestion"
            }
          }
        }
      }
    }
  }
}

run "creates_governed_catalog_hierarchy" {
  command = plan

  assert {
    condition     = databricks_catalog.this["analytics"].storage_root == "s3://company-data-dev/managed/analytics"
    error_message = "The catalog must use its configured managed storage root."
  }

  assert {
    condition     = databricks_schema.this["analytics.curated"].catalog_name == "analytics" && databricks_volume.this["analytics.curated.reference"].volume_type == "MANAGED"
    error_message = "Schemas and managed volumes must be created within their catalog hierarchy."
  }

  assert {
    condition     = databricks_volume.this["analytics.curated.ingestion"].volume_type == "EXTERNAL" && databricks_volume.this["analytics.curated.ingestion"].storage_location == "s3://company-data-dev/landing/ingestion"
    error_message = "External volumes must preserve their configured storage location."
  }

  assert {
    condition     = length(databricks_grants.catalog["analytics"].grant) == 1 && length(databricks_grants.schema["analytics.curated"].grant) == 1 && length(databricks_grants.volume["analytics.curated.reference"].grant) == 1
    error_message = "Configured grants must be managed at each requested hierarchy level."
  }
}

run "creates_no_objects_by_default" {
  command = plan

  variables {
    catalogs = {}
  }

  assert {
    condition     = length(databricks_catalog.this) == 0 && length(databricks_schema.this) == 0 && length(databricks_volume.this) == 0
    error_message = "The module must not create governance objects unless explicitly configured."
  }
}

run "rejects_external_volume_without_storage_location" {
  command = plan

  variables {
    catalogs = {
      analytics = {
        schemas = {
          curated = {
            volumes = {
              invalid = {
                volume_type = "EXTERNAL"
              }
            }
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.validation]
}
