locals {
  memberships = merge({}, [for group_name, group in var.groups : {
    for member_name, member_id in group.member_ids : jsonencode([group_name, member_name]) => {
      group_name = group_name
      member_id  = member_id
    }
  }]...)
}

resource "databricks_group" "this" {
  provider     = databricks.accounts
  for_each     = var.groups
  display_name = each.key
}

resource "databricks_access_control_rule_set" "group_managers" {
  provider = databricks.accounts
  for_each = { for name, group in var.groups : name => group if length(group.manager_group_names) > 0 }
  name     = "accounts/${coalesce(var.databricks_account_id, "missing-account-id")}/groups/${databricks_group.this[each.key].id}/ruleSets/default"

  grant_rules {
    role       = "roles/group.manager"
    principals = [for name in sort(tolist(each.value.manager_group_names)) : databricks_group.this[name].acl_principal_id]
  }

  lifecycle {
    precondition {
      condition     = var.databricks_account_id != null
      error_message = "databricks_account_id is required for group manager delegation."
    }
  }
}

resource "databricks_group_member" "this" {
  provider  = databricks.accounts
  for_each  = local.memberships
  group_id  = databricks_group.this[each.value.group_name].id
  member_id = each.value.member_id
}

resource "databricks_mws_permission_assignment" "this" {
  provider     = databricks.accounts
  for_each     = var.groups
  workspace_id = var.workspace_id
  principal_id = databricks_group.this[each.key].id
  permissions  = [each.value.workspace_permission]
}
