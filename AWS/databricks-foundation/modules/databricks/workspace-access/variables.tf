variable "workspace_id" {
  description = "Existing identity-federated workspace ID."
  type        = number
  nullable    = false
  validation {
    condition     = var.workspace_id > 0 && floor(var.workspace_id) == var.workspace_id
    error_message = "workspace_id must be a positive integer."
  }
}

variable "groups" {
  description = "Workspace permission groups; membership is externally managed. External groups require reviewed account SCIM IDs."
  type = map(object({
    display_name     = string
    lifecycle        = string
    account_group_id = optional(string)
    workspace_role   = string
    entitlements = object({
      workspace_access           = bool
      databricks_sql_access      = bool
      allow_cluster_create       = optional(bool, false)
      allow_instance_pool_create = optional(bool, false)
    })
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([for group in values(var.groups) :
      contains(["create", "external"], group.lifecycle) && contains(["USER", "ADMIN"], group.workspace_role) &&
      length(trimspace(group.display_name)) > 0 && group.display_name == trimspace(group.display_name) &&
      !contains(["admins", "users"], group.display_name) &&
      (group.lifecycle == "external" ? can(regex("^[1-9][0-9]*$", group.account_group_id)) : group.account_group_id == null)
    ]) && length(distinct([for group in values(var.groups) : group.display_name])) == length(var.groups)
    error_message = "Groups need unique non-reserved names, create/external lifecycle, USER/ADMIN role, and an ID only for external groups."
  }
}
