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
mock_provider "databricks" { alias = "accounts" }
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
  state_bucket               = "example-terraform-state"
  state_region               = "eu-central-1"
  databricks_account_id      = "12345678-1234-1234-1234-123456789abc"
  create_metastore           = false
  existing_metastore_id      = "12345678-1234-1234-1234-123456789abc"
  catalog_name               = "dev_analytics"
  observability              = { catalog_name = "dev_operations" }
  enable_init_scripts_volume = true
  init_script_readers        = []
  catalog_grants             = {}
  schema_grants              = {}
  incoming_volume_grants     = {}
  external_locations         = {}
  catalogs                   = {}
}
override_data {
  target = data.terraform_remote_state.infra
  values = { outputs = {
    aws_region = "eu-west-1"
    data_storage_buckets = {
      landing       = { arn = "arn:aws:s3:::dev-landing", url = "s3://dev-landing" }
      uc_managed    = { arn = "arn:aws:s3:::dev-managed", url = "s3://dev-managed" }
      observability = { arn = "arn:aws:s3:::dev-logs", url = "s3://dev-logs" }
    }
  } }
}
override_data {
  target = data.terraform_remote_state.account
  values = { outputs = {
    aws_region    = "eu-west-1"
    workspace_id  = 123456789
    workspace_url = "https://test-dev.cloud.databricks.com"
  } }
}

run "existing_metastore_and_compute_storage" {
  command = apply
  assert {
    condition     = databricks_metastore_assignment.existing["dev"].workspace_id == 123456789 && output.metastore_id == "12345678-1234-1234-1234-123456789abc"
    error_message = "Data access must assign the metastore using the workspace ID from account state."
  }
  assert {
    condition     = contains(keys(output.catalog_ids), "dev_analytics") && contains(keys(output.catalog_ids), "dev_operations") && length(output.storage_credential_names) == 3 && length(output.external_location_ids) == 3
    error_message = "The data-access phase must own analytics and operations storage before compute configuration."
  }
  assert {
    condition     = output.cluster_log_volume_path == "/Volumes/dev_operations/observability/cluster_logs" && output.init_scripts_volume_path == "/Volumes/dev_operations/observability/init_scripts"
    error_message = "Both compute volume paths must be available from the data-access root."
  }
}
run "new_metastore_path" {
  command = plan
  variables {
    create_metastore      = true
    existing_metastore_id = ""
  }
  assert {
    condition     = length(module.unity_catalog_metastore) == 1 && length(databricks_metastore_assignment.existing) == 0
    error_message = "An explicitly requested metastore must be created in data-access instead of workspace configuration."
  }
}
