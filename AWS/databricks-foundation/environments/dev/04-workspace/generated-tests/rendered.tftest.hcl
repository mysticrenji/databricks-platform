# Run with -var-file=<offline-render>/compute.tfvars.json. All providers are mocked.
mock_provider "databricks" { alias = "workspace" }
variables {
  groups                          = {}
  service_principals              = {}
  jobs                            = {}
  register_infra_instance_profile = false
  instance_profile_group_names    = []
  cluster_log_volume_path         = null
  init_script_volume_path         = null
  enable_hello_world_init_script  = false
  state_bucket                    = "example-terraform-state"
  state_region                    = "eu-central-1"
}
override_data {
  target = data.terraform_remote_state.infra
  values = { outputs = {} }
}
override_data {
  target = data.terraform_remote_state.account
  values = { outputs = {
    workspace_id  = 123456789
    workspace_url = "https://test-dev.cloud.databricks.com"
  } }
}
run "rendered_compute_and_persona_permissions" {
  command = plan
  assert {
    condition     = length(data.terraform_remote_state.data_access) == 0
    error_message = "Generated compute must not depend on root 03."
  }
  assert {
    condition     = toset(keys(output.cluster_policy_ids)) == toset(["engineering-standard", "ml-standard"]) && toset(keys(output.warehouse_ids)) == toset(["analytics"])
    error_message = "Both persona policies and the analytics warehouse must reach the existing root 04 modules."
  }
  assert {
    condition = (
      var.cluster_policies["engineering-standard"].permissions.groups == tomap({ "dev-demo-engineers" = "CAN_USE" }) &&
      var.cluster_policies["ml-standard"].permissions.groups == tomap({ "dev-demo-ml" = "CAN_USE" }) &&
      var.warehouses["analytics"].permissions.groups == tomap({
        "dev-demo-admins"    = "CAN_MANAGE"
        "dev-demo-engineers" = "CAN_USE"
        "dev-demo-analysts"  = "CAN_USE"
        "dev-demo-ml"        = "CAN_USE"
      })
    )
    error_message = "Rendered ACLs must give each persona only its declared policy and SQL warehouse permission."
  }
  assert {
    condition     = length(output.group_ids) == 0 && length(output.instance_profile_ids) == 0 && length(output.job_ids) == 0 && output.hello_world_init_script_path == null
    error_message = "Persona compute must not create local groups, instance profiles, jobs, or init scripts."
  }
}
