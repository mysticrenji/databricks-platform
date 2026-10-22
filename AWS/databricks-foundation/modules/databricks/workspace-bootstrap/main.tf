resource "databricks_group" "this" {
  provider = databricks.workspace
  for_each = var.groups

  display_name               = each.key
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume
  databricks_sql_access      = each.value.databricks_sql_access
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
}

resource "databricks_service_principal" "this" {
  provider = databricks.workspace
  for_each = var.service_principals

  display_name               = each.key
  active                     = each.value.active
  workspace_access           = each.value.workspace_access
  workspace_consume          = each.value.workspace_consume
  databricks_sql_access      = each.value.databricks_sql_access
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
}
