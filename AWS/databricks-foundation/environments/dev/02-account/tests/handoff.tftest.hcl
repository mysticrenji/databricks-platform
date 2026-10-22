mock_provider "databricks" {
  alias = "accounts"
  mock_resource "databricks_group" {
    defaults = { id = "500" }
  }
}
variables {
  state_bucket          = "example-terraform-state"
  state_region          = "eu-central-1"
  databricks_account_id = "12345678-1234-1234-1234-123456789abc"
  workspace_name        = "test-dev"
}
override_data {
  target = data.terraform_remote_state.infra
  values = { outputs = {
    deployment_environment              = "dev"
    deployment_workspace                = "shared"
    aws_region                          = "eu-central-1"
    databricks_cross_account_role_arn   = "arn:aws:iam::123456789012:role/databricks-cross-account"
    root_storage_bucket_name            = "databricks-dev-root-123456789012"
    vpc_id                              = "vpc-0123456789abcdef0"
    workspace_subnet_ids                = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    workspace_security_group_id         = "sg-0123456789abcdef0"
    workspace_instance_profile_arn      = "arn:aws:iam::123456789012:instance-profile/databricks-compute"
    workspace_instance_profile_role_arn = "arn:aws:iam::123456789012:role/databricks-compute"
  } }
}
run "uses_infra_state_for_workspace_creation" {
  command = plan
  assert {
    condition     = module.workspace != null && output.aws_region == "eu-central-1"
    error_message = "Account setup must consume the region from the infrastructure state."
  }
}

run "rejects_another_workspaces_infrastructure" {
  command = plan
  variables {
    workspace_key = "sandbox"
  }
  expect_failures = [data.terraform_remote_state.infra]
}

run "demo_groups_follow_workspace_creation" {
  command = apply
  variables {
    account_groups = jsondecode(file("../../../platform/terraform-inputs/dev/demo.02-account.json")).account_groups
  }
  override_module {
    target = module.workspace
    outputs = {
      workspace_id  = 12345
      workspace_url = "https://example.cloud.databricks.com"
    }
  }
  assert {
    condition     = output.workspace_id == 12345 && toset(keys(output.account_group_ids)) == toset(["dev-demo-admins", "dev-demo-engineers", "dev-demo-analysts", "dev-demo-ml"])
    error_message = "Root 02 must create the demo groups using its new workspace ID."
  }
}
