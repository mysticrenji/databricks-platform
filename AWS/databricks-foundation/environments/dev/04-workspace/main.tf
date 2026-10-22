data "terraform_remote_state" "infra" {
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.infra_state_key }
}

data "terraform_remote_state" "account" {
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.account_state_key }
}

data "terraform_remote_state" "data_access" {
  count   = var.read_data_access_state ? 1 : 0
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.data_access_state_key }
}

# Bind the optional generated compute deployment to the existing account root.
resource "terraform_data" "compute_binding" {
  count = var.compute_identity == null ? 0 : 1
  input = var.compute_identity

  lifecycle {
    precondition {
      condition = (
        var.infra_state_key == "databricks/dev/demo/01-infra.tfstate" &&
        var.account_state_key == "databricks/dev/demo/02-account.tfstate"
      )
      error_message = "Generated persona compute requires the dev/demo upstream state namespace."
    }
    precondition {
      condition = (
        tostring(data.terraform_remote_state.account.outputs.workspace_id) == var.compute_identity.workspace_id &&
        data.terraform_remote_state.account.outputs.workspace_url == var.compute_identity.workspace_url
      )
      error_message = "Compute identity must match the workspace ID and URL exported by root 02."
    }
    precondition {
      condition = alltrue([
        for name, id in var.compute_group_ids :
        try(data.terraform_remote_state.account.outputs.account_group_ids[name] == id, false)
      ])
      error_message = "Compute group IDs must exactly match the corresponding root 02 account groups."
    }
  }
}

# 21. Configure explicitly requested workspace-local identities.
module "workspace_bootstrap" {
  source             = "../../../modules/databricks/workspace-bootstrap"
  providers          = { databricks.workspace = databricks.workspace }
  groups             = var.groups
  service_principals = var.service_principals
}

# 22. Register the AWS compute instance profile only when needed.
module "instance_profiles" {
  source    = "../../../modules/databricks/instance-profiles"
  providers = { databricks.workspace = databricks.workspace }
  instance_profiles = var.register_infra_instance_profile ? {
    infra = {
      instance_profile_arn = data.terraform_remote_state.infra.outputs.workspace_instance_profile_arn
      iam_role_arn         = data.terraform_remote_state.infra.outputs.workspace_instance_profile_role_arn
      group_ids_by_name    = { for name in var.instance_profile_group_names : name => module.workspace_bootstrap.group_ids[name] }
    }
  } : {}
}

# 23. Cluster policies
module "cluster_policies" {
  source                         = "../../../modules/databricks/cluster-policies"
  providers                      = { databricks.workspace = databricks.workspace }
  cluster_policies               = var.cluster_policies
  cluster_log_volume_path        = var.cluster_log_volume_path
  init_script_volume_path        = var.init_script_volume_path
  enable_hello_world_init_script = var.enable_hello_world_init_script
  depends_on                     = [module.workspace_bootstrap, terraform_data.compute_binding]
}

# 24. Sql warehouses
module "sql_warehouses" {
  source     = "../../../modules/databricks/sql-warehouses"
  providers  = { databricks.workspace = databricks.workspace }
  warehouses = var.warehouses
  depends_on = [module.workspace_bootstrap, terraform_data.compute_binding]
}

# 25. Job
module "job" {
  source     = "../../../modules/databricks/job"
  providers  = { databricks.workspace = databricks.workspace }
  jobs       = var.jobs
  depends_on = [module.workspace_bootstrap, terraform_data.compute_binding]
}
