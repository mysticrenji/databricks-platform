resource "databricks_external_location" "this" {
  provider = databricks.workspace
  for_each = var.external_locations

  name               = each.key
  url                = each.value.url
  credential_name    = each.value.credential_name
  owner              = each.value.owner
  comment            = each.value.comment
  read_only          = each.value.read_only
  enable_file_events = each.value.enable_file_events
  skip_validation    = each.value.skip_validation
}

resource "databricks_grants" "external_location" {
  provider = databricks.workspace
  for_each = {
    for name, location in var.external_locations : name => location
    if length(location.grants) > 0
  }

  external_location = databricks_external_location.this[each.key].name

  dynamic "grant" {
    for_each = each.value.grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}
