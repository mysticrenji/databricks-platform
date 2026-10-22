mock_provider "databricks" {
  alias = "accounts"
}

variables {
  name                        = "databricks-dev-eu-central-1"
  databricks_account_id       = "12345678-1234-1234-1234-123456789abc"
  cross_account_role_arn      = "arn:aws:iam::123456789012:role/databricks-dev-cross-account"
  root_storage_bucket_name    = "databricks-dev-eu-central-1-root-123456789012"
  vpc_id                      = "vpc-0123456789abcdef0"
  workspace_subnet_ids        = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
  workspace_security_group_id = "sg-0123456789abcdef0"
}

run "registers_all_required_account_configuration_objects" {
  command = plan

  assert {
    condition     = databricks_mws_credentials.this.credentials_name == "databricks-dev-eu-central-1-credentials"
    error_message = "Credential configuration must use the stable credentials name."
  }

  assert {
    condition     = databricks_mws_storage_configurations.this.bucket_name == "databricks-dev-eu-central-1-root-123456789012"
    error_message = "Storage configuration must reference the root storage bucket."
  }

  assert {
    condition     = databricks_mws_networks.this.vpc_id == "vpc-0123456789abcdef0" && contains(databricks_mws_networks.this.security_group_ids, "sg-0123456789abcdef0")
    error_message = "Network configuration must reference the intended VPC and workspace security group."
  }
}

run "rejects_single_subnet" {
  command = plan
  variables {
    workspace_subnet_ids = ["subnet-0123456789abcdef0"]
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_duplicate_subnets" {
  command = plan
  variables {
    workspace_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef0"]
  }
  expect_failures = [terraform_data.validation]
}
