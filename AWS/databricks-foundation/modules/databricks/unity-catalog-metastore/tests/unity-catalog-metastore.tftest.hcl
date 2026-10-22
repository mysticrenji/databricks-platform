mock_provider "databricks" {
  alias = "accounts"
}

variables {
  metastore_name = "company-eu-central-1"
  aws_region     = "eu-central-1"
  workspace_id   = 123456789
  owner          = "uc-admins"
}

run "creates_and_assigns_metastore_without_shared_root" {
  command = plan

  assert {
    condition     = databricks_metastore.this.name == "company-eu-central-1" && databricks_metastore.this.region == "eu-central-1"
    error_message = "The metastore must use the configured name and AWS Region."
  }

  assert {
    condition     = databricks_metastore_assignment.workspace.workspace_id == 123456789
    error_message = "The metastore must be assigned to the requested workspace."
  }

  assert {
    condition     = databricks_metastore.this.storage_root == null && databricks_metastore.this.storage_root_credential_id == null
    error_message = "The default configuration must not create a shared metastore storage root."
  }
}

run "allows_shared_root_with_existing_credential" {
  command = plan

  variables {
    storage_root               = "s3://company-uc-eu-central-1/metastore"
    storage_root_credential_id = "credential-123"
  }

  assert {
    condition     = databricks_metastore.this.storage_root == "s3://company-uc-eu-central-1/metastore" && databricks_metastore.this.storage_root_credential_id == "credential-123"
    error_message = "A shared root must use the supplied storage credential."
  }
}

run "rejects_unpaired_storage_root" {
  command = plan

  variables {
    storage_root = "s3://company-uc-eu-central-1/metastore"
  }

  expect_failures = [terraform_data.validation]
}
