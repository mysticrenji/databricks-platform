locals {
  schemas = {
    for definition in flatten([
      for catalog_key, catalog in var.catalogs : [
        for schema_key, schema in catalog.schemas : {
          key         = "${catalog_key}.${schema_key}"
          catalog_key = catalog_key
          schema_key  = schema_key
          definition  = schema
        }
      ]
    ]) : definition.key => definition
  }

  volumes = {
    for definition in flatten([
      for catalog_key, catalog in var.catalogs : [
        for schema_key, schema in catalog.schemas : [
          for volume_key, volume in schema.volumes : {
            key         = "${catalog_key}.${schema_key}.${volume_key}"
            catalog_key = catalog_key
            schema_key  = schema_key
            volume_key  = volume_key
            definition  = volume
          }
        ]
      ]
    ]) : definition.key => definition
  }

  catalog_grants = {
    for key, catalog in var.catalogs : key => catalog
    if length(catalog.grants) > 0
  }

  schema_grants = {
    for key, schema in local.schemas : key => schema
    if length(schema.definition.grants) > 0
  }

  volume_grants = {
    for key, volume in local.volumes : key => volume
    if length(volume.definition.grants) > 0
  }
}

resource "terraform_data" "validation" {
  input = var.catalogs

  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for catalog in values(var.catalogs) : [
          for schema in values(catalog.schemas) : [
            for volume in values(schema.volumes) : (volume.volume_type == "EXTERNAL") == (volume.storage_location != null)
          ]
        ]
      ]))
      error_message = "EXTERNAL volumes require storage_location, while MANAGED volumes must not set storage_location."
    }
  }
}

resource "databricks_catalog" "this" {
  provider = databricks.workspace
  for_each = var.catalogs

  name         = each.key
  comment      = each.value.comment
  owner        = each.value.owner
  storage_root = each.value.storage_root
  properties   = each.value.properties
}

resource "databricks_schema" "this" {
  provider = databricks.workspace
  for_each = local.schemas

  catalog_name = databricks_catalog.this[each.value.catalog_key].name
  name         = each.value.schema_key
  comment      = each.value.definition.comment
  owner        = each.value.definition.owner
  storage_root = each.value.definition.storage_root
  properties   = each.value.definition.properties

  depends_on = [terraform_data.validation]
}

resource "databricks_volume" "this" {
  provider = databricks.workspace
  for_each = local.volumes

  catalog_name     = databricks_catalog.this[each.value.catalog_key].name
  schema_name      = databricks_schema.this["${each.value.catalog_key}.${each.value.schema_key}"].name
  name             = each.value.volume_key
  volume_type      = each.value.definition.volume_type
  storage_location = each.value.definition.storage_location
  comment          = each.value.definition.comment
  owner            = each.value.definition.owner

  depends_on = [terraform_data.validation]
}

resource "databricks_grants" "catalog" {
  provider = databricks.workspace
  for_each = local.catalog_grants

  catalog = databricks_catalog.this[each.key].name

  dynamic "grant" {
    for_each = each.value.grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_grants" "schema" {
  provider = databricks.workspace
  for_each = local.schema_grants

  schema = databricks_schema.this[each.key].id

  dynamic "grant" {
    for_each = each.value.definition.grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_grants" "volume" {
  provider = databricks.workspace
  for_each = local.volume_grants

  volume = databricks_volume.this[each.key].id

  dynamic "grant" {
    for_each = each.value.definition.grants

    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}
