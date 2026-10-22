variable "name" {
  description = "Prefix for the IAM roles and policy."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name) && length(var.name) <= 45
    error_message = "name must be non-empty, have no leading or trailing whitespace, and be at most 45 characters."
  }
}

variable "databricks_account_id" {
  description = "Databricks account ID used as the external ID in the cross-account trust policy."
  type        = string
  nullable    = false
  sensitive   = true

  validation {
    condition     = length(trimspace(var.databricks_account_id)) > 0 && var.databricks_account_id == trimspace(var.databricks_account_id)
    error_message = "databricks_account_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "databricks_control_plane_account_id" {
  description = "Databricks AWS control-plane account trusted by the cross-account role. Use the documented value for your AWS partition."
  type        = string
  default     = "414351767826"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.databricks_control_plane_account_id))
    error_message = "databricks_control_plane_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_partition" {
  description = "AWS partition used in IAM ARNs, for example aws or aws-us-gov."
  type        = string
  default     = "aws"
  nullable    = false

  validation {
    condition     = contains(["aws", "aws-us-gov"], var.aws_partition)
    error_message = "aws_partition must be aws or aws-us-gov."
  }
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary ARN applied to both roles."
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Additional tags applied to all IAM resources. Resource Name tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
