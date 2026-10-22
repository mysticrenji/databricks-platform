data "terraform_remote_state" "infra" {
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.infra_state_key }
}

data "terraform_remote_state" "account" {
  backend = "s3"
  config  = { bucket = var.state_bucket, region = var.state_region, key = var.account_state_key }
}

# 16. Create a metastore only if the region does not already have one.
module "unity_catalog_metastore" {
  for_each       = var.create_metastore ? { dev = true } : {}
  source         = "../../../modules/databricks/unity-catalog-metastore"
  providers      = { databricks.accounts = databricks.accounts }
  metastore_name = var.metastore_name
  aws_region     = data.terraform_remote_state.account.outputs.aws_region
  workspace_id   = tonumber(data.terraform_remote_state.account.outputs.workspace_id)
}

# Alternatively, attach the workspace to an existing regional metastore.
resource "databricks_metastore_assignment" "existing" {
  for_each     = !var.create_metastore && var.existing_metastore_id != "" ? { dev = var.existing_metastore_id } : {}
  provider     = databricks.accounts
  metastore_id = each.value
  workspace_id = tonumber(data.terraform_remote_state.account.outputs.workspace_id)
}


# 19. Optional additional external locations using existing credentials.
module "external_locations" {
  source             = "../../../modules/databricks/external-locations"
  providers          = { databricks.workspace = databricks.workspace }
  external_locations = var.external_locations
  depends_on         = [module.unity_catalog_metastore, databricks_metastore_assignment.existing]
}

# 20. Optional additional catalogs; do not duplicate data_access catalog names.
module "catalogs" {
  source     = "../../../modules/databricks/catalogs"
  providers  = { databricks.workspace = databricks.workspace }
  catalogs   = var.catalogs
  depends_on = [module.unity_catalog_metastore, databricks_metastore_assignment.existing, module.external_locations]
}

# 17-20. Credentials → UC IAM roles → external locations → optional catalog.
module "data_access" {
  source                     = "../../../modules/databricks/data-access"
  providers                  = { databricks.workspace = databricks.workspace }
  name                       = "databricks-dev-${data.terraform_remote_state.infra.outputs.aws_region}"
  buckets                    = data.terraform_remote_state.infra.outputs.data_storage_buckets
  catalog_name               = var.catalog_name
  catalog_grants             = var.catalog_grants
  schema_grants              = var.schema_grants
  incoming_volume_grants     = var.incoming_volume_grants
  observability              = var.observability
  enable_init_scripts_volume = var.enable_init_scripts_volume
  init_script_readers        = var.init_script_readers
  depends_on                 = [module.unity_catalog_metastore, databricks_metastore_assignment.existing]
}
