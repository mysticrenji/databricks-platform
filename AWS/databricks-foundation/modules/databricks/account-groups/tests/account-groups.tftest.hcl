mock_provider "databricks" {
  alias = "accounts"
  mock_resource "databricks_group" {
    defaults = { id = "500", acl_principal_id = "groups/platform-admins" }
  }
}

variables {
  workspace_id = 12345
  groups = {
    platform-admins = {
      workspace_permission = "ADMIN"
      member_ids           = { me = "100", automation = "200" }
    }
    platform-users = { member_ids = { me = "100" } }
  }
}

run "assigns_existing_members_and_workspace_roles" {
  command = apply
  assert {
    condition     = length(databricks_group.this) == 2 && length(databricks_group_member.this) == 3
    error_message = "Both account groups and all declared membership pairs must be created."
  }
  assert {
    condition     = databricks_group_member.this[jsonencode(["platform-admins", "automation"])].member_id == "200" && databricks_group_member.this[jsonencode(["platform-admins", "automation"])].group_id == output.group_ids["platform-admins"]
    error_message = "The existing service principal must join the intended account group."
  }
  assert {
    condition     = databricks_mws_permission_assignment.this["platform-admins"].workspace_id == 12345 && tostring(databricks_mws_permission_assignment.this["platform-admins"].principal_id) == output.group_ids["platform-admins"] && toset(databricks_mws_permission_assignment.this["platform-admins"].permissions) == toset(["ADMIN"])
    error_message = "The admin group must receive ADMIN on the specified workspace."
  }
  assert {
    condition     = toset(databricks_mws_permission_assignment.this["platform-users"].permissions) == toset(["USER"])
    error_message = "Workspace access must default to USER."
  }
}

run "empty_configuration_creates_nothing" {
  command = plan
  variables { groups = {} }
  assert {
    condition     = length(databricks_group.this) == 0 && length(databricks_group_member.this) == 0 && length(databricks_mws_permission_assignment.this) == 0
    error_message = "An empty configuration must create no identities or assignments."
  }
}

run "demo_bootstrap_assigns_groups_without_managing_membership" {
  command = apply
  variables {
    groups = jsondecode(file("../../../platform/terraform-inputs/dev/demo.02-account.json")).account_groups
  }
  assert {
    condition     = toset(keys(output.group_ids)) == toset(["dev-demo-admins", "dev-demo-engineers", "dev-demo-analysts", "dev-demo-ml"])
    error_message = "Provisioning inputs must create the four demo account groups."
  }
  assert {
    condition = length(databricks_mws_permission_assignment.this) == 4 && alltrue([
      for name, assignment in databricks_mws_permission_assignment.this :
      assignment.workspace_id == 12345 && tostring(assignment.principal_id) == output.group_ids[name] &&
      toset(assignment.permissions) == toset([name == "dev-demo-admins" ? "ADMIN" : "USER"])
    ])
    error_message = "Each demo group must be assigned to this workspace with its approved role."
  }
  assert {
    condition     = length(databricks_group_member.this) == 0 && length(databricks_access_control_rule_set.group_managers) == 0
    error_message = "Bootstrap must leave membership and group management external."
  }
}

run "delegates_membership_without_workspace_admin" {
  command = apply
  variables {
    databricks_account_id = "00000000-0000-0000-0000-000000000001"
    groups = {
      platform-admins = { workspace_permission = "ADMIN" }
      developers      = { manager_group_names = ["platform-admins"] }
      readers         = { manager_group_names = ["platform-admins"] }
    }
  }
  assert {
    condition = length(databricks_access_control_rule_set.group_managers) == 2 && alltrue([
      for rule in values(databricks_access_control_rule_set.group_managers) :
      one(rule.grant_rules).role == "roles/group.manager" && toset(one(rule.grant_rules).principals) == toset(["groups/platform-admins"])
    ])
    error_message = "Only the two delegated groups should have explicit group-manager rules for platform admins."
  }
  assert {
    condition = alltrue([for name in ["developers", "readers"] :
      toset(databricks_mws_permission_assignment.this[name].permissions) == toset(["USER"])
    ]) && length(databricks_group_member.this) == 0
    error_message = "Delegation must not grant workspace ADMIN or invent members."
  }
}

run "rejects_undeclared_manager_group" {
  command = plan
  variables {
    groups = { developers = { manager_group_names = ["missing"] } }
  }
  expect_failures = [var.groups]
}

run "rejects_account_admin_permission" {
  command = plan
  variables { groups = { platform-admins = { workspace_permission = "ACCOUNT_ADMIN" } } }
  expect_failures = [var.groups]
}

run "rejects_oauth_client_id_as_member_id" {
  command = plan
  variables { groups = { platform-admins = { member_ids = { automation = "12345678-1234-1234-1234-123456789abc" } } } }
  expect_failures = [var.groups]
}

run "rejects_duplicate_members" {
  command = plan
  variables { groups = { platform-admins = { member_ids = { me = "100", duplicate = "100" } } } }
  expect_failures = [var.groups]
}

run "rejects_blank_group_name" {
  command = plan
  variables { groups = { " " = {} } }
  expect_failures = [var.groups]
}

run "rejects_invalid_workspace_id" {
  command = plan
  variables { workspace_id = 0 }
  expect_failures = [var.workspace_id]
}

run "rejects_reserved_group_name" {
  command = plan
  variables { groups = { admins = {} } }
  expect_failures = [var.groups]
}
