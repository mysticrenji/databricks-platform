resource "databricks_mws_workspaces" "this" {
  provider = databricks.accounts

  account_id               = var.databricks_account_id
  aws_region               = var.aws_region
  workspace_name           = var.workspace_name
  credentials_id           = var.credentials_id
  storage_configuration_id = var.storage_configuration_id
  network_id               = var.network_id
  pricing_tier             = var.pricing_tier
}
