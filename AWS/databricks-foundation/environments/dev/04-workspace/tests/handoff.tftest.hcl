mock_provider "databricks" { alias = "workspace" }
variables {
  cluster_log_volume_path         = null
  init_script_volume_path         = null
  enable_hello_world_init_script  = false
  state_bucket                    = "example-terraform-state"
  state_region                    = "eu-central-1"
  groups                          = { "test-engineers" = {} }
  register_infra_instance_profile = true
  instance_profile_group_names    = ["test-engineers"]
}
override_data {
  target = data.terraform_remote_state.infra
  values = { outputs = {
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
override_data {
  target = data.terraform_remote_state.account
  values = { outputs = {
    aws_region    = "eu-central-1"
    workspace_id  = 123456789
    workspace_url = "https://test-dev.cloud.databricks.com"
  } }
}
override_data {
  target = data.terraform_remote_state.data_access[0]
  values = { outputs = {
    metastore_id          = "12345678-1234-1234-1234-123456789abc"
    catalog_ids           = { dev_analytics = "dev_analytics" }
    external_location_ids = { managed = "managed-location" }
  } }
}
run "uses_data_access_and_infra_state" {
  command = plan
  assert {
    condition     = output.metastore_id == "12345678-1234-1234-1234-123456789abc" && output.catalog_ids.dev_analytics == "dev_analytics" && output.external_location_ids.managed == "managed-location"
    error_message = "Workspace configuration must read data-object IDs from 03-data-access instead of owning them."
  }
  assert {
    condition     = contains(keys(output.instance_profile_ids), "infra")
    error_message = "Registration must include the instance profile from infra state."
  }
}
run "compute_paths_after_data_access" {
  command = plan
  variables {
    cluster_log_volume_path        = "/Volumes/dev_operations/observability/cluster_logs"
    init_script_volume_path        = "/Volumes/dev_operations/observability/init_scripts/hello-world.sh"
    enable_hello_world_init_script = true
    cluster_policies = {
      demo = { definition = { "num_workers" = { type = "fixed", value = 0 } } }
    }
  }
  assert {
    condition     = output.hello_world_init_script_path == "/Volumes/dev_operations/observability/init_scripts/hello-world.sh" && contains(keys(output.cluster_policy_ids), "demo")
    error_message = "The compute phase must upload the script and configure its policy after the data-access phase."
  }
}

run "compute_only_skips_data_access" {
  command = plan
  variables {
    read_data_access_state = false
    infra_state_key        = "databricks/dev/demo/01-infra.tfstate"
    account_state_key      = "databricks/dev/demo/02-account.tfstate"
    compute_identity = {
      environment   = "dev"
      workspace     = "demo"
      account_id    = "12345678-1234-1234-1234-123456789abc"
      workspace_id  = "123456789"
      workspace_url = "https://test-dev.cloud.databricks.com"
    }
    compute_group_ids = { "dev-demo-engineers" = "12345" }
  }
  override_data {
    target = data.terraform_remote_state.account
    values = { outputs = {
      workspace_id      = 123456789
      workspace_url     = "https://test-dev.cloud.databricks.com"
      account_group_ids = { "dev-demo-engineers" = "12345" }
    } }
  }
  assert {
    condition     = length(data.terraform_remote_state.data_access) == 0 && output.metastore_id == null && length(output.catalog_ids) == 0 && length(output.external_location_ids) == 0
    error_message = "Generated compute must not read root 03 or require a metastore."
  }
  assert {
    condition     = output.target_identity.workspace == "demo" && output.compute_group_ids["dev-demo-engineers"] == "12345"
    error_message = "Compute outputs must retain the verified target and group bindings."
  }
}

run "rejects_wrong_workspace" {
  command = plan
  variables {
    read_data_access_state = false
    infra_state_key        = "databricks/dev/demo/01-infra.tfstate"
    account_state_key      = "databricks/dev/demo/02-account.tfstate"
    compute_identity = {
      environment   = "dev"
      workspace     = "demo"
      account_id    = "12345678-1234-1234-1234-123456789abc"
      workspace_id  = "999999999"
      workspace_url = "https://test-dev.cloud.databricks.com"
    }
  }
  expect_failures = [terraform_data.compute_binding]
}

run "rejects_wrong_groups" {
  command = plan
  variables {
    read_data_access_state = false
    infra_state_key        = "databricks/dev/demo/01-infra.tfstate"
    account_state_key      = "databricks/dev/demo/02-account.tfstate"
    compute_identity = {
      environment   = "dev"
      workspace     = "demo"
      account_id    = "12345678-1234-1234-1234-123456789abc"
      workspace_id  = "123456789"
      workspace_url = "https://test-dev.cloud.databricks.com"
    }
    compute_group_ids = { "dev-demo-engineers" = "99999" }
  }
  expect_failures = [terraform_data.compute_binding]
}

run "rejects_unbound_volume_paths" {
  command = plan
  variables {
    read_data_access_state  = false
    cluster_log_volume_path = "/Volumes/dev_operations/observability/cluster_logs"
  }
  expect_failures = [var.read_data_access_state]
}
