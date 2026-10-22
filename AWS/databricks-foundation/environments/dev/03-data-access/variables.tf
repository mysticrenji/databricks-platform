variable "state_bucket" {
  description = "Existing S3 state bucket containing infra and account states."
  type        = string
  nullable    = false
}
variable "state_region" {
  description = "AWS region of the existing Terraform state bucket."
  type        = string
  nullable    = false
}
variable "infra_state_key" {
  description = "S3 state key for 01-infra."
  type        = string
  default     = "databricks/dev/shared/01-infra.tfstate"
  nullable    = false
}
variable "account_state_key" {
  description = "S3 state key for 02-account."
  type        = string
  default     = "databricks/dev/shared/02-account.tfstate"
  nullable    = false
}
variable "catalog_grants" {
  description = "Authoritative grants for the optional catalog. Empty leaves grants unmanaged."
  type        = map(set(string))
  default     = {}
  nullable    = false
}

variable "observability" {
  description = "Optional operations catalog and managed cluster-log volume in the dedicated observability bucket. Grants are authoritative per object."
  type = object({
    catalog_name   = string
    schema_name    = optional(string, "observability")
    volume_name    = optional(string, "cluster_logs")
    catalog_grants = optional(map(set(string)), {})
    schema_grants  = optional(map(set(string)), {})
    volume_grants  = optional(map(set(string)), {})
  })
  default  = null
  nullable = true
  validation {
    condition = var.observability == null ? true : alltrue([
      for name in [var.observability.catalog_name, var.observability.schema_name, var.observability.volume_name] :
      can(regex("^[a-z][a-z0-9_]{0,254}$", name))
    ])
    error_message = "Operations catalog, schema, and volume names must be lowercase identifiers starting with a letter."
  }
}

variable "catalog_name" {
  description = "Optional learning catalog. Null registers storage access only."
  type        = string
  default     = null
  nullable    = true
}

variable "schema_grants" {
  description = "Authoritative grants by learning schema, then principal. Empty leaves grants unmanaged."
  type        = map(map(set(string)))
  default     = {}
  nullable    = false
}

variable "incoming_volume_grants" {
  description = "Authoritative grants on the ingestion incoming volume. Empty leaves grants unmanaged."
  type        = map(set(string))
  default     = {}
  nullable    = false
}
variable "enable_init_scripts_volume" {
  description = "Create a managed init_scripts volume in the operations schema. File uploads are managed separately by cluster-policies."
  type        = bool
  default     = false
  nullable    = false
}

variable "init_script_readers" {
  description = "Account principals granted READ_VOLUME on the optional init_scripts volume; parent usage is configured through observability grants."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "databricks_account_id" {
  description = "Databricks account ID used by the account provider."
  type        = string
  nullable    = false
}

variable "create_metastore" {
  description = "Create a new regional metastore; leave false when reusing an existing metastore."
  type        = bool
  nullable    = false
  default     = false
}

variable "metastore_name" {
  description = "Regional metastore name when creating a metastore."
  type        = string
  nullable    = false
  default     = "databricks-dev-eu-central-1"
}

variable "existing_metastore_id" {
  description = "Existing regional metastore ID to assign; empty means no assignment requested."
  type        = string
  nullable    = false
  default     = ""
}

variable "external_locations" {
  description = "Unity Catalog external locations keyed by their Databricks name. Each location references an existing storage credential and may define authoritative grants."
  type = map(object({
    url                = string
    credential_name    = string
    owner              = optional(string)
    comment            = optional(string)
    read_only          = optional(bool, false)
    enable_file_events = optional(bool, false)
    skip_validation    = optional(bool, false)
    grants             = optional(map(set(string)), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.external_locations) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each external location name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for location in values(var.external_locations) : can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", location.url))])
    error_message = "Each external location url must be a valid s3:// bucket path."
  }

  validation {
    condition     = length(distinct([for location in values(var.external_locations) : location.url])) == length(var.external_locations)
    error_message = "Each external location must use a distinct S3 URL."
  }

  validation {
    condition     = alltrue([for location in values(var.external_locations) : length(trimspace(location.credential_name)) > 0 && location.credential_name == trimspace(location.credential_name)])
    error_message = "Each credential_name must be non-empty with no leading or trailing whitespace."
  }

  validation {
    condition = alltrue(flatten([
      for location in values(var.external_locations) : [
        for principal, privileges in location.grants : length(trimspace(principal)) > 0 && principal == trimspace(principal) && length(privileges) > 0 && alltrue([for privilege in privileges : length(trimspace(privilege)) > 0 && privilege == trimspace(privilege)])
      ]
    ]))
    error_message = "Each grant must have a non-empty principal and at least one non-empty privilege."
  }
}

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
