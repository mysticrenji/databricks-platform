variable "cluster_log_volume_path" {
  description = "Optional existing UC volume path enforced for logging on all configured compute policies. Create the volume before applying."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.cluster_log_volume_path == null || can(regex("^/Volumes/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*(/.*)?$", var.cluster_log_volume_path))
    error_message = "Use an absolute /Volumes/catalog/schema/volume path."
  }
}

variable "cluster_policies" {
  description = "Cluster policies keyed by display name. Define a policy JSON object or a policy family and overrides, with optional authoritative permissions."
  type = map(object({
    description                        = optional(string)
    definition                         = optional(any)
    policy_family_id                   = optional(string)
    policy_family_definition_overrides = optional(any)
    max_clusters_per_user              = optional(number)
    permissions = optional(object({
      groups             = optional(map(string), {})
      service_principals = optional(map(string), {})
      users              = optional(map(string), {})
    }), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.cluster_policies) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each cluster policy name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition = alltrue(flatten([
      for policy in values(var.cluster_policies) : [
        policy.max_clusters_per_user == null ? true : (policy.max_clusters_per_user > 0 && floor(policy.max_clusters_per_user) == policy.max_clusters_per_user),
        alltrue([for level in values(policy.permissions.groups) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(policy.permissions.service_principals) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(policy.permissions.users) : contains(["CAN_USE", "CAN_MANAGE"], level)])
      ]
    ]))
    error_message = "max_clusters_per_user must be a positive whole number, and cluster policy permissions must be CAN_USE or CAN_MANAGE."
  }
}
variable "init_script_volume_path" {
  description = "Optional existing UC shell script fixed at init-script index zero on all configured compute policies."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.init_script_volume_path == null || can(regex("^/Volumes/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[^\\r\\n]+\\.sh$", var.init_script_volume_path))
    error_message = "Use an absolute /Volumes/catalog/schema/volume/script.sh path."
  }
}
variable "enable_hello_world_init_script" {
  description = "Upload the bundled hello-world script to init_script_volume_path before configuring compute policies. The UC volume must already exist."
  type        = bool
  default     = false
  nullable    = false
}
