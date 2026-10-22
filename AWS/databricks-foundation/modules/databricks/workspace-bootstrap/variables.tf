variable "groups" {
  description = "Workspace-local groups to create, keyed by display name. Keep compute and SQL entitlements disabled unless a group requires them."
  type = map(object({
    workspace_access           = optional(bool, true)
    workspace_consume          = optional(bool)
    databricks_sql_access      = optional(bool, false)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.groups) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each group name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for group in values(var.groups) : !(group.workspace_access && group.workspace_consume == true)])
    error_message = "workspace_access and workspace_consume cannot both be enabled for a group."
  }
}

variable "service_principals" {
  description = "Workspace-local automation service principals to create, keyed by display name. Prefer account-level service principals with identity federation where available."
  type = map(object({
    active                     = optional(bool, true)
    workspace_access           = optional(bool, true)
    workspace_consume          = optional(bool)
    databricks_sql_access      = optional(bool, false)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.service_principals) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each service principal name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for service_principal in values(var.service_principals) : !(service_principal.workspace_access && service_principal.workspace_consume == true)])
    error_message = "workspace_access and workspace_consume cannot both be enabled for a service principal."
  }
}
