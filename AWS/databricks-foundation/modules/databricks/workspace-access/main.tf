module "created" {
  source       = "../account-groups"
  providers    = { databricks.accounts = databricks.accounts }
  workspace_id = var.workspace_id
  groups = { for group in values(var.groups) : group.display_name => {
    workspace_permission = group.workspace_role
  } if group.lifecycle == "create" }
}

data "databricks_group" "external" {
  provider     = databricks.accounts
  for_each     = { for key, group in var.groups : key => group if group.lifecycle == "external" }
  display_name = each.value.display_name
  recursive    = false
  lifecycle {
    postcondition {
      condition     = self.id == each.value.account_group_id
      error_message = "External group name must resolve to the reviewed account group ID."
    }
  }
}

locals {
  group_ids = { for key, group in var.groups : key => (
    group.lifecycle == "create" ? module.created.group_ids[group.display_name] : data.databricks_group.external[key].id
  ) }
}

resource "databricks_mws_permission_assignment" "external" {
  provider     = databricks.accounts
  for_each     = { for key, group in var.groups : key => group if group.lifecycle == "external" }
  workspace_id = var.workspace_id
  principal_id = local.group_ids[each.key]
  permissions  = [each.value.workspace_role]
}

resource "databricks_entitlements" "this" {
  provider                   = databricks.workspace
  for_each                   = var.groups
  group_id                   = local.group_ids[each.key]
  workspace_access           = each.value.entitlements.workspace_access
  databricks_sql_access      = each.value.entitlements.databricks_sql_access
  allow_cluster_create       = each.value.entitlements.allow_cluster_create
  allow_instance_pool_create = each.value.entitlements.allow_instance_pool_create
  depends_on                 = [module.created, databricks_mws_permission_assignment.external]
}
