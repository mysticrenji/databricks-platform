variable "name" {
  description = "Unique environment/region prefix for roles, credentials, and external locations."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name))
    error_message = "name must be 1-40 letters, numbers, underscores, or hyphens."
  }
}

variable "buckets" {
  description = "Existing infra bucket ARNs and URLs keyed by landing, uc_managed, and optional observability."
  type        = map(object({ arn = string, url = string }))
  nullable    = false
  validation {
    condition     = alltrue([for key in ["landing", "uc_managed"] : contains(keys(var.buckets), key)]) && alltrue([for key, bucket in var.buckets : contains(["landing", "uc_managed", "observability"], key) && can(regex("^arn:aws(-us-gov)?:s3:::[a-z0-9.-]+$", bucket.arn)) && try(bucket.url == "s3://${split(":::", bucket.arn)[1]}", false)])
    error_message = "Provide landing and uc_managed, optionally observability, with matching S3 ARNs and URLs."
  }
}

variable "catalog_grants" {
  description = "Authoritative grants for the optional catalog, keyed by account group, user, or service principal. Empty leaves grants unmanaged."
  type        = map(set(string))
  default     = {}
  nullable    = false
}

variable "schema_grants" {
  description = "Authoritative grants by schema name, then principal. Empty maps leave grants unmanaged."
  type        = map(map(set(string)))
  default     = {}
  nullable    = false
  validation {
    condition     = alltrue([for name in keys(var.schema_grants) : contains(["bronze", "silver", "gold", "ingestion"], name)])
    error_message = "Schema grants may only target bronze, silver, gold, or ingestion."
  }
}

variable "incoming_volume_grants" {
  description = "Authoritative grants for ingestion.incoming, keyed by principal. Empty leaves grants unmanaged."
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
  description = "Optional learning catalog with bronze, silver, gold, and an ingestion incoming volume. Null creates no catalog."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.catalog_name == null || can(regex("^[a-z][a-z0-9_]{0,254}$", var.catalog_name))
    error_message = "catalog_name must be null or a lowercase identifier starting with a letter."
  }
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
