locals {
  init_script_rules = var.init_script_volume_path == null ? {} : {
    "init_scripts.0.volumes.destination" = { type = "fixed", value = var.init_script_volume_path }
  }
  log_rules = var.cluster_log_volume_path == null ? {} : {
    "cluster_log_conf.type" = { type = "fixed", value = "VOLUMES", hidden = true }
    "cluster_log_conf.path" = { type = "fixed", value = var.cluster_log_volume_path, hidden = true }
  }
  policies_with_permissions = {
    for name, policy in var.cluster_policies : name => policy
    if length(policy.permissions.groups) + length(policy.permissions.service_principals) + length(policy.permissions.users) > 0
  }
}

resource "terraform_data" "validation" {
  input = var.cluster_policies

  lifecycle {
    precondition {
      condition     = !var.enable_hello_world_init_script || var.init_script_volume_path != null
      error_message = "Set init_script_volume_path to the destination file in an existing UC volume when enabling the hello-world upload."
    }
    precondition {
      condition = var.init_script_volume_path == null || alltrue(flatten([
        for policy in values(var.cluster_policies) : [
          for key in keys(merge(policy.definition, policy.policy_family_definition_overrides)) :
          !startswith(key, "init_scripts.0.") || key == "init_scripts.0.volumes.destination"
        ]
      ]))
      error_message = "Index zero is reserved for the configured volume script; remove other init_scripts.0 source settings."
    }
    precondition {
      condition = var.cluster_log_volume_path == null || alltrue(flatten([
        for policy in values(var.cluster_policies) : [
          for key in keys(merge(policy.definition, policy.policy_family_definition_overrides)) :
          !startswith(key, "cluster_log_conf.") || contains(["cluster_log_conf.type", "cluster_log_conf.path"], key)
        ]
      ]))
      error_message = "Volume logging cannot be combined with other cluster_log_conf fields; remove the old S3/DBFS logging settings."
    }
    precondition {
      condition = alltrue([
        for policy in values(var.cluster_policies) : (policy.definition == null) != (policy.policy_family_id == null)
      ])
      error_message = "Each cluster policy must set exactly one of definition or policy_family_id."
    }

    precondition {
      condition = alltrue([
        for policy in values(var.cluster_policies) : policy.policy_family_definition_overrides == null || policy.policy_family_id != null
      ])
      error_message = "policy_family_definition_overrides can only be used with policy_family_id."
    }
  }
}

resource "databricks_cluster_policy" "this" {
  provider = databricks.workspace
  for_each = var.cluster_policies

  name                               = each.key
  description                        = each.value.description
  definition                         = each.value.definition == null ? null : jsonencode(merge(each.value.definition, local.log_rules, local.init_script_rules))
  policy_family_id                   = each.value.policy_family_id
  policy_family_definition_overrides = each.value.policy_family_definition_overrides == null && ((var.cluster_log_volume_path == null && var.init_script_volume_path == null) || each.value.policy_family_id == null) ? null : jsonencode(merge(each.value.policy_family_definition_overrides, each.value.policy_family_id == null ? {} : local.log_rules, each.value.policy_family_id == null ? {} : local.init_script_rules))
  max_clusters_per_user              = each.value.max_clusters_per_user

  depends_on = [terraform_data.validation, databricks_file.hello_world_init_script]
}

resource "databricks_file" "hello_world_init_script" {
  provider       = databricks.workspace
  for_each       = var.enable_hello_world_init_script && var.init_script_volume_path != null ? { hello = true } : {}
  path           = var.init_script_volume_path
  content_base64 = filebase64("${path.module}/scripts/hello-world.sh")
}

resource "databricks_permissions" "cluster_policy" {
  provider = databricks.workspace
  for_each = local.policies_with_permissions

  cluster_policy_id = databricks_cluster_policy.this[each.key].id

  dynamic "access_control" {
    for_each = each.value.permissions.groups

    content {
      group_name       = access_control.key
      permission_level = access_control.value
    }
  }

  dynamic "access_control" {
    for_each = each.value.permissions.service_principals

    content {
      service_principal_name = access_control.key
      permission_level       = access_control.value
    }
  }

  dynamic "access_control" {
    for_each = each.value.permissions.users

    content {
      user_name        = access_control.key
      permission_level = access_control.value
    }
  }
}
