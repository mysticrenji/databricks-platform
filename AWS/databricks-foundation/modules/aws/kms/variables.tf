variable "enabled" {
  description = "Whether to create a customer-managed KMS key and attach its usage policies. Defaults to false."
  type        = bool
  default     = false
  nullable    = false
}

variable "name" {
  description = "Prefix for the KMS key alias and IAM policies."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name) && can(regex("^[a-zA-Z0-9/_+=,.@-]+$", var.name))
    error_message = "name must be non-empty, have no leading or trailing whitespace, and use IAM/KMS alias-safe characters."
  }
}

variable "aws_region" {
  description = "AWS region containing the key and root storage bucket."
  type        = string
  nullable    = false
}

variable "aws_account_id" {
  description = "AWS account ID that owns the KMS key. Required only when enabled is true."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.aws_account_id == null || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be null or a 12-digit AWS account ID."
  }
}

variable "cross_account_role_name" {
  description = "Databricks cross-account role name to receive KMS usage permission. Required only when enabled is true."
  type        = string
  default     = null
  nullable    = true
}

variable "workspace_instance_profile_role_name" {
  description = "Workspace EC2 role name to receive KMS usage permission. Required only when enabled is true."
  type        = string
  default     = null
  nullable    = true
}

variable "aws_partition" {
  description = "AWS partition used in IAM ARNs."
  type        = string
  default     = "aws"
  nullable    = false

  validation {
    condition     = contains(["aws", "aws-us-gov"], var.aws_partition)
    error_message = "aws_partition must be aws or aws-us-gov."
  }
}

variable "deletion_window_in_days" {
  description = "KMS key deletion waiting period. AWS permits 7 through 30 days."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be between 7 and 30."
  }
}

variable "tags" {
  description = "Additional tags applied to the KMS key. The Name tag takes precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
