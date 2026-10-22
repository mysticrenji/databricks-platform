variable "account_id" {
  description = "Verified Databricks account UUID."
  type        = string
  nullable    = false
}
variable "workspace_id" {
  description = "Verified existing workspace ID."
  type        = number
  nullable    = false
}
variable "workspace_url" {
  description = "Verified existing AWS workspace URL."
  type        = string
  nullable    = false
}
variable "metastore_id" {
  description = "Verified assigned metastore UUID; never created or assigned here."
  type        = string
  nullable    = false
}
variable "groups" {
  description = "Validated groups; lifecycle terraform references root 02 bootstrap groups without managing their assignments or entitlements."
  type = map(object({
    display_name = string, lifecycle = string, account_group_id = optional(string), workspace_role = string
    entitlements = object({
      workspace_access     = bool, databricks_sql_access = bool
      allow_cluster_create = optional(bool, false), allow_instance_pool_create = optional(bool, false)
    })
  }))
  nullable = false
}
variable "grants" {
  description = "Complete union of managed direct group privileges on existing data objects."
  type = map(object({
    object_type = string, object_name = string, group_key = string, privileges = set(string)
  }))
  nullable = false
  validation {
    condition     = alltrue([for grant in values(var.grants) : contains(keys(var.groups), grant.group_key)])
    error_message = "Every grant must reference a registered group."
  }
}
