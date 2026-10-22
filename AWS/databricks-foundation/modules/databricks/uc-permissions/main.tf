resource "databricks_grant" "this" {
  provider   = databricks.workspace
  for_each   = var.grants
  catalog    = each.value.object_type == "catalog" ? each.value.object_name : null
  schema     = each.value.object_type == "schema" ? each.value.object_name : null
  table      = each.value.object_type == "table" ? each.value.object_name : null
  principal  = each.value.principal
  privileges = each.value.privileges
}
