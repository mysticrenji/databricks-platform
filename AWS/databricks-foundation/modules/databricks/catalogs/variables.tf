variable "catalogs" {
  description = "Unity Catalog catalogs keyed by catalog name, with optional schemas, volumes, and authoritative grants at each level."
  type = map(object({
    comment      = optional(string)
    owner        = optional(string)
    storage_root = optional(string)
    properties   = optional(map(string), {})
    grants       = optional(map(set(string)), {})
    schemas = optional(map(object({
      comment      = optional(string)
      owner        = optional(string)
      storage_root = optional(string)
      properties   = optional(map(string), {})
      grants       = optional(map(set(string)), {})
      volumes = optional(map(object({
        comment          = optional(string)
        owner            = optional(string)
        volume_type      = optional(string, "MANAGED")
        storage_location = optional(string)
        grants           = optional(map(set(string)), {})
      })), {})
    })), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.catalogs) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each catalog name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition = alltrue(flatten([
      for catalog in values(var.catalogs) : [
        for schema_name, schema in catalog.schemas : length(trimspace(schema_name)) > 0 && schema_name == trimspace(schema_name) && alltrue([for volume_name, volume in schema.volumes : length(trimspace(volume_name)) > 0 && volume_name == trimspace(volume_name) && contains(["MANAGED", "EXTERNAL"], volume.volume_type)])
      ]
    ]))
    error_message = "Schema and volume names must be non-empty without surrounding whitespace, and volume_type must be MANAGED or EXTERNAL."
  }

  validation {
    condition = alltrue(concat(
      [for catalog in values(var.catalogs) : catalog.storage_root == null || can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", catalog.storage_root))],
      flatten([for catalog in values(var.catalogs) : [for schema in values(catalog.schemas) : schema.storage_root == null || can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", schema.storage_root))]]),
      flatten([for catalog in values(var.catalogs) : [for schema in values(catalog.schemas) : [for volume in values(schema.volumes) : volume.storage_location == null || can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", volume.storage_location))]]])
    ))
    error_message = "Catalog and schema storage roots, and volume storage locations, must be null or valid s3:// bucket paths."
  }
}
