module "workspace_entitlements" {
  source    = "../../../modules/databricks/workspace-entitlements"
  providers = { databricks.workspace = databricks.workspace }
  groups    = var.groups
}
