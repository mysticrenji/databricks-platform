locals {
  warehouses_with_permissions = {
    for name, warehouse in var.warehouses : name => warehouse
    if length(warehouse.permissions.groups) + length(warehouse.permissions.service_principals) + length(warehouse.permissions.users) > 0
  }
}

resource "terraform_data" "validation" {
  input = var.warehouses

  lifecycle {
    precondition {
      condition = alltrue([
        for warehouse in values(var.warehouses) : warehouse.min_num_clusters <= warehouse.max_num_clusters
      ])
      error_message = "min_num_clusters must not exceed max_num_clusters for any warehouse."
    }
  }
}

resource "databricks_sql_endpoint" "this" {
  provider = databricks.workspace
  for_each = var.warehouses

  name                      = each.key
  cluster_size              = each.value.cluster_size
  auto_stop_mins            = each.value.auto_stop_mins
  min_num_clusters          = each.value.min_num_clusters
  max_num_clusters          = each.value.max_num_clusters
  enable_photon             = each.value.enable_photon
  enable_serverless_compute = each.value.enable_serverless_compute
  warehouse_type            = each.value.warehouse_type
  spot_instance_policy      = each.value.spot_instance_policy

  dynamic "tags" {
    for_each = length(each.value.tags) > 0 ? [each.value.tags] : []

    content {
      dynamic "custom_tags" {
        for_each = tags.value

        content {
          key   = custom_tags.key
          value = custom_tags.value
        }
      }
    }
  }

  depends_on = [terraform_data.validation]
}

resource "databricks_permissions" "warehouse" {
  provider = databricks.workspace
  for_each = local.warehouses_with_permissions

  sql_endpoint_id = databricks_sql_endpoint.this[each.key].id

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
