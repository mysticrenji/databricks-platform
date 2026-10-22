variable "name" {
  description = "Name of the Kinesis Data Stream."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]{1,128}$", var.name))
    error_message = "name must be 1-128 characters using letters, numbers, periods, underscores, or hyphens."
  }
}

variable "workspace_instance_profile_role_name" {
  description = "Name of the EC2 role used by the Databricks workspace instance profile."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.workspace_instance_profile_role_name)) > 0 && var.workspace_instance_profile_role_name == trimspace(var.workspace_instance_profile_role_name)
    error_message = "workspace_instance_profile_role_name must be non-empty with no leading or trailing whitespace."
  }
}

variable "retention_period_hours" {
  description = "How long Kinesis retains records, in hours."
  type        = number
  default     = 24
  nullable    = false

  validation {
    condition     = var.retention_period_hours >= 24 && var.retention_period_hours <= 8760
    error_message = "retention_period_hours must be between 24 and 8760."
  }
}

variable "tags" {
  description = "Additional tags applied to the Kinesis stream. The Name tag takes precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
