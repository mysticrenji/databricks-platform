module "workspace_access" {
  source = "../../../modules/databricks/workspace-access"
  providers = {
    databricks.accounts  = databricks.accounts
    databricks.workspace = databricks.workspace
  }
  workspace_id = var.workspace_id
  groups       = { for key, group in var.groups : key => group if group.lifecycle != "terraform" }
}

data "databricks_group" "bootstrap" {
  provider     = databricks.accounts
  for_each     = { for key, group in var.groups : key => group if group.lifecycle == "terraform" }
  display_name = each.value.display_name
  recursive    = false
  lifecycle {
    postcondition {
      # Offline generated-input tests use mocked lookup; live runner binds root 02 IDs.
      condition     = each.value.account_group_id == null || self.id == each.value.account_group_id
      error_message = "Bootstrap group must match the verified root 02 account group ID."
    }
  }
}

locals {
  group_ids = merge(module.workspace_access.group_ids, {
    for key, group in data.databricks_group.bootstrap : key => group.id
  })
}

module "uc_permissions" {
  source    = "../../../modules/databricks/uc-permissions"
  providers = { databricks.workspace = databricks.workspace }
  grants = { for key, grant in var.grants : key => {
    object_type = grant.object_type
    object_name = grant.object_name
    principal   = var.groups[grant.group_key].display_name
    privileges  = grant.privileges
  } }
  depends_on = [module.workspace_access, data.databricks_group.bootstrap]
}
