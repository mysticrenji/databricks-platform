mock_provider "aws" {}

variables {
  name       = "databricks-dev-eu-central-1"
  aws_region = "eu-central-1"
}

run "is_disabled_by_default" {
  command = plan

  assert {
    condition     = output.enabled == false && output.key_arn == null
    error_message = "The KMS module must not create or expose a key unless enabled."
  }
}

run "creates_rotating_key_and_role_permissions_when_enabled" {
  command = plan
  variables {
    enabled                              = true
    aws_account_id                       = "123456789012"
    cross_account_role_name              = "databricks-dev-cross-account"
    workspace_instance_profile_role_name = "databricks-dev-instance-profile"
  }

  assert {
    condition     = aws_kms_key.workspace[0].enable_key_rotation
    error_message = "Customer-managed keys must enable automatic rotation."
  }

  assert {
    condition     = aws_iam_role_policy.cross_account_kms[0].role == "databricks-dev-cross-account"
    error_message = "The cross-account role needs the KMS usage policy."
  }

  assert {
    condition     = aws_kms_alias.workspace[0].name == "alias/databricks-dev-eu-central-1-root-storage"
    error_message = "The KMS alias must use the module naming convention."
  }
}

run "requires_identity_inputs_when_enabled" {
  command = plan
  variables {
    enabled = true
  }
  expect_failures = [terraform_data.validation]
}
