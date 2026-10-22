data "terraform_remote_state" "infra" {
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.infra_state_key }
  lifecycle {
    postcondition {
      condition = (
        try(self.outputs.deployment_environment, null) == var.environment_name &&
        try(self.outputs.deployment_workspace, null) == var.workspace_key
      )
      error_message = "Infrastructure state must belong to the selected environment and workspace."
    }
  }
}

# 12. Register the infrastructure produced by 01-infra.
module "account_configuration" {
  source                      = "../../../modules/databricks/account-configuration"
  providers                   = { databricks.accounts = databricks.accounts }
  name                        = var.workspace_name
  databricks_account_id       = var.databricks_account_id
  cross_account_role_arn      = data.terraform_remote_state.infra.outputs.databricks_cross_account_role_arn
  root_storage_bucket_name    = data.terraform_remote_state.infra.outputs.root_storage_bucket_name
  vpc_id                      = data.terraform_remote_state.infra.outputs.vpc_id
  workspace_subnet_ids        = data.terraform_remote_state.infra.outputs.workspace_subnet_ids
  workspace_security_group_id = data.terraform_remote_state.infra.outputs.workspace_security_group_id
}

# 13. Create the workspace using the registered configuration IDs.
module "workspace" {
  source                   = "../../../modules/databricks/workspace"
  providers                = { databricks.accounts = databricks.accounts }
  databricks_account_id    = var.databricks_account_id
  workspace_name           = var.workspace_name
  aws_region               = data.terraform_remote_state.infra.outputs.aws_region
  pricing_tier             = var.pricing_tier
  credentials_id           = module.account_configuration.credentials_id
  storage_configuration_id = module.account_configuration.storage_configuration_id
  network_id               = module.account_configuration.network_id
}

# 14. Account identities and their access to this workspace.
module "account_groups" {
  source                = "../../../modules/databricks/account-groups"
  providers             = { databricks.accounts = databricks.accounts }
  workspace_id          = module.workspace.workspace_id
  groups                = var.account_groups
  databricks_account_id = var.databricks_account_id
}

# 15. Monthly workspace budget alerts when recipients are configured.
module "account_budget" {
  for_each                    = length(var.budget_alert_email_addresses) > 0 ? { workspace = true } : {}
  source                      = "../../../modules/databricks/account-budgets"
  providers                   = { databricks.accounts = databricks.accounts }
  name                        = "${var.workspace_name}-monthly"
  workspace_ids               = [module.workspace.workspace_id]
  monthly_limit_usd           = var.monthly_budget_usd
  alert_email_addresses       = var.budget_alert_email_addresses
  alert_threshold_percentages = var.budget_alert_threshold_percentages
}
