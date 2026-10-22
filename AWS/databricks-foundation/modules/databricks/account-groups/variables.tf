variable "databricks_account_id" {
  description = "Databricks account UUID. Required when delegating group management."
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_id" {
  description = "ID of the identity-federated workspace to assign the account groups to."
  type        = number
  nullable    = false
  validation {
    condition     = var.workspace_id > 0 && floor(var.workspace_id) == var.workspace_id
    error_message = "workspace_id must be a positive integer."
  }
}

variable "groups" {
  description = "Account groups keyed by display name. Member maps use stable logical names and existing account SCIM IDs; workspace permission defaults to USER."
  type = map(object({
    member_ids           = optional(map(string), {})
    workspace_permission = optional(string, "USER")
    manager_group_names  = optional(set(string), [])
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue(flatten([for group in values(var.groups) : [
      for name in group.manager_group_names : contains(keys(var.groups), name)
    ]]))
    error_message = "Manager groups must also be declared in groups."
  }
  validation {
    condition     = alltrue([for name in keys(var.groups) : length(trimspace(name)) > 0 && name == trimspace(name) && !contains(["users", "admins"], name)])
    error_message = "Group names must be non-empty without surrounding whitespace and must not be the reserved names users or admins."
  }
  validation {
    condition     = alltrue([for group in values(var.groups) : contains(["USER", "ADMIN"], group.workspace_permission)])
    error_message = "workspace_permission must be USER or ADMIN."
  }
  validation {
    condition     = alltrue(flatten([for group in values(var.groups) : [for name, id in group.member_ids : length(trimspace(name)) > 0 && name == trimspace(name) && can(regex("^[0-9]+$", id))]]))
    error_message = "Member keys must be non-empty without surrounding whitespace; member IDs must be numeric account SCIM IDs, not OAuth client IDs."
  }
  validation {
    condition     = alltrue([for group in values(var.groups) : length(distinct(values(group.member_ids))) == length(group.member_ids)])
    error_message = "A member ID must occur only once within each group."
  }
}
