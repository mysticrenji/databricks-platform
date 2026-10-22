variable "environment_name" {
  description = "Provisioning environment; initially dev only."
  type        = string
  nullable    = false
  validation {
    condition     = var.environment_name == "dev"
    error_message = "Only the dev environment is supported."
  }
}
variable "workspace_key" {
  description = "Workspace namespace from the verified provisioning target."
  type        = string
  nullable    = false
  validation {
    condition     = length(var.workspace_key) <= 16 && can(regex("^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$", var.workspace_key))
    error_message = "Workspace key must be a lowercase slug of at most 16 characters."
  }
}
variable "account_id" {
  description = "Verified Databricks account UUID."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.account_id))
    error_message = "Account ID must be a UUID."
  }
}
variable "workspace_id" {
  description = "Verified numeric workspace ID exported by root 02."
  type        = number
  nullable    = false
  validation {
    condition     = var.workspace_id > 0 && floor(var.workspace_id) == var.workspace_id
    error_message = "Workspace ID must be a positive integer."
  }
}
variable "workspace_url" {
  description = "Verified HTTPS AWS Databricks workspace URL exported by root 02."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^https://[a-z0-9][a-z0-9-]*[.]cloud[.]databricks[.]com$", var.workspace_url))
    error_message = "Workspace URL must be an HTTPS AWS Databricks workspace host."
  }
}
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
}
