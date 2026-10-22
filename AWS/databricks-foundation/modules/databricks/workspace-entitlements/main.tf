resource "databricks_entitlements" "this" {
  provider                   = databricks.workspace
  for_each                   = var.groups
  group_id                   = each.value.group_id
  workspace_access           = each.value.workspace_access
  databricks_sql_access      = each.value.databricks_sql_access
  allow_cluster_create       = each.value.allow_cluster_create
  allow_instance_pool_create = each.value.allow_instance_pool_create
}
