variable "groups" {
  description = "Verified existing account groups keyed by stable persona, with explicit workspace feature entitlements. Membership and workspace assignments are externally owned."
  type = map(object({
    group_id                   = string
    workspace_role             = string
    workspace_access           = bool
    databricks_sql_access      = bool
    allow_cluster_create       = bool
    allow_instance_pool_create = bool
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for group in values(var.groups) : can(regex("^[1-9][0-9]*$", group.group_id))])
    error_message = "Group IDs must be positive numeric account SCIM IDs."
  }
  validation {
    condition     = length(distinct([for group in values(var.groups) : group.group_id])) == length(var.groups)
    error_message = "Each account group ID must have exactly one entitlement owner."
  }
  validation {
    condition     = alltrue([for group in values(var.groups) : contains(["USER", "ADMIN"], group.workspace_role)])
    error_message = "Workspace roles must be USER or ADMIN."
  }
  validation {
    condition     = alltrue([for group in values(var.groups) : group.workspace_role != "USER" || (!group.allow_cluster_create && !group.allow_instance_pool_create && (group.workspace_access || group.databricks_sql_access))])
    error_message = "USER groups require workspace or SQL access and cannot create unrestricted clusters or instance pools."
  }
  validation {
    condition     = alltrue([for group in values(var.groups) : group.workspace_role != "ADMIN" || (group.workspace_access && group.databricks_sql_access && group.allow_cluster_create && group.allow_instance_pool_create)])
    error_message = "ADMIN groups must retain workspace, SQL, unrestricted cluster and instance pool capabilities."
  }
}
