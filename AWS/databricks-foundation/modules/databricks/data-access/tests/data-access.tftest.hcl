mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/test-uc-role" }
  }
}
mock_provider "databricks" {
  alias = "workspace"
  mock_resource "databricks_volume" {
    defaults = { volume_path = "/Volumes/dev_operations/observability/cluster_logs" }
  }
  mock_resource "databricks_storage_credential" {
    defaults = {
      aws_iam_role = {
        external_id           = "generated-credential-id"
        unity_catalog_iam_arn = "arn:aws:iam::414351767826:role/uc-master"
      }
    }
  }
}
mock_provider "time" {}

variables {
  name = "dev"
  buckets = {
    landing    = { arn = "arn:aws:s3:::dev-landing", url = "s3://dev-landing" }
    uc_managed = { arn = "arn:aws:s3:::dev-managed", url = "s3://dev-managed" }
  }
}

run "single_apply_without_bootstrap" {
  command = apply
  assert {
    condition     = output.credential_names == { landing = "dev-landing", uc_managed = "dev-uc_managed" } && length(output.external_location_ids) == 2 && length(output.catalog_ids) == 0
    error_message = "One apply must register both storage paths without creating an unrequested catalog."
  }
}

run "optional_medallion_catalog" {
  command = apply
  variables {
    catalog_name = "dev_analytics"
    catalog_grants = {
      "databricks-dev-admins"    = ["ALL_PRIVILEGES", "MANAGE"]
      "databricks-dev-developer" = ["BROWSE", "USE_CATALOG"]
      "databricks-dev-reader"    = ["BROWSE", "USE_CATALOG"]
    }
    schema_grants = {
      bronze = { "databricks-dev-developer" = ["USE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"] }
      silver = { "databricks-dev-developer" = ["USE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"] }
      gold = {
        "databricks-dev-developer" = ["USE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"]
        "databricks-dev-reader"    = ["USE_SCHEMA", "SELECT"]
      }
      ingestion = { "databricks-dev-developer" = ["USE_SCHEMA"] }
    }
    incoming_volume_grants = { "databricks-dev-developer" = ["READ_VOLUME", "WRITE_VOLUME"] }
  }
  assert {
    condition     = contains(keys(output.catalog_ids), "dev_analytics")
    error_message = "The explicitly requested learning catalog must be created."
  }
}

run "rejects_unknown_schema" {
  command = plan
  variables { schema_grants = { typo = {} } }
  expect_failures = [var.schema_grants]
}

run "dedicated_operations_storage" {
  command = apply
  variables {
    buckets = {
      landing       = { arn = "arn:aws:s3:::dev-landing", url = "s3://dev-landing" }
      uc_managed    = { arn = "arn:aws:s3:::dev-managed", url = "s3://dev-managed" }
      observability = { arn = "arn:aws:s3:::dev-logs", url = "s3://dev-logs" }
    }
    observability = {
      catalog_name   = "dev_operations"
      catalog_grants = { "databricks-dev-admins" = ["ALL_PRIVILEGES", "MANAGE"] }
      schema_grants  = { "databricks-dev-developer" = ["USE_SCHEMA"] }
      volume_grants  = { "databricks-dev-developer" = ["READ_VOLUME", "WRITE_VOLUME"] }
    }
  }
  assert {
    condition     = length(output.role_arns) == 3 && length(output.credential_names) == 3 && length(output.external_location_ids) == 3 && contains(keys(output.catalog_ids), "dev_operations") && output.cluster_log_volume_path == "/Volumes/dev_operations/observability/cluster_logs"
    error_message = "Operations storage must receive its own IAM role, credential, external location, and UC log volume."
  }
}

run "rejects_operations_without_logs_bucket" {
  command = plan
  variables { observability = { catalog_name = "dev_operations" } }
  expect_failures = [terraform_data.observability_validation]
}
run "creates_script_volume_without_uploading_files" {
  command = apply
  variables {
    buckets = {
      landing       = { arn = "arn:aws:s3:::dev-landing", url = "s3://dev-landing" }
      uc_managed    = { arn = "arn:aws:s3:::dev-managed", url = "s3://dev-managed" }
      observability = { arn = "arn:aws:s3:::dev-logs", url = "s3://dev-logs" }
    }
    observability              = { catalog_name = "dev_operations" }
    enable_init_scripts_volume = true
    init_script_readers        = ["databricks-dev-developer"]
  }
  assert {
    condition     = output.init_scripts_volume_path == "/Volumes/dev_operations/observability/init_scripts" && contains(keys(module.observability_catalog.volume_ids), "dev_operations.observability.init_scripts")
    error_message = "The script volume must exist for the compute-policy module to upload files."
  }
}

run "rejects_script_without_operations_catalog" {
  command = plan
  variables {
    enable_init_scripts_volume = true
    observability              = null
  }
  expect_failures = [terraform_data.observability_validation]
}
