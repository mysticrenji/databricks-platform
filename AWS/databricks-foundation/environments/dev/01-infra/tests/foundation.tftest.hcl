mock_provider "aws" {}

variables {
  aws_region       = "eu-central-1"
  environment_name = "dev"
  workspace_key    = "shared"
  vpc_cidr_block   = "10.20.0.0/16"
  workspace_subnets = {
    a = { availability_zone = "eu-central-1a", cidr_block = "10.20.0.0/20" }
    b = { availability_zone = "eu-central-1b", cidr_block = "10.20.16.0/20" }
  }
  nat_subnets = {
    a = { availability_zone = "eu-central-1a", cidr_block = "10.20.240.0/24" }
  }
  workspace_subnet_nat_gateway_keys = { a = "a", b = "a" }
  endpoint_subnets = {
    a = { availability_zone = "eu-central-1a", cidr_block = "10.20.242.0/24" }
    b = { availability_zone = "eu-central-1b", cidr_block = "10.20.243.0/24" }
  }
  databricks_account_id    = "12345678-1234-1234-1234-123456789abc"
  root_storage_bucket_name = "databricks-dev-root-123456789012"
}

run "exports_infrastructure_contract" {
  command = plan
  assert {
    condition     = output.aws_region == "eu-central-1"
    error_message = "The infrastructure state must export the workspace region."
  }
  assert {
    condition     = length(output.workspace_subnet_ids) == 2
    error_message = "The account state needs two workspace subnets."
  }
  assert {
    condition     = output.root_storage_bucket_name == "databricks-dev-root-123456789012"
    error_message = "The account state must use the root-storage bucket from this phase."
  }
}

run "names_and_tags_are_scoped_to_workspace" {
  command = plan
  variables {
    environment_name = "staging"
    workspace_key    = "sandbox"
  }
  assert {
    condition     = module.iam_roles.cross_account_role_name == "databricks-staging-sandbox-cross-account"
    error_message = "IAM names must include both environment and workspace."
  }
  assert {
    condition     = output.deployment_environment == "staging" && output.deployment_workspace == "sandbox"
    error_message = "Infrastructure outputs must identify their environment and workspace."
  }
}
