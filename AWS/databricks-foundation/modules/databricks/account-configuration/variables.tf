variable "name" {
  description = "Prefix for Databricks account configuration object names."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name) && length(var.name) <= 80
    error_message = "name must be non-empty, have no leading or trailing whitespace, and be at most 80 characters."
  }
}

variable "databricks_account_id" {
  description = "Databricks account ID for account-level configuration resources."
  type        = string
  nullable    = false
  sensitive   = true

  validation {
    condition     = length(trimspace(var.databricks_account_id)) > 0 && var.databricks_account_id == trimspace(var.databricks_account_id)
    error_message = "databricks_account_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "cross_account_role_arn" {
  description = "AWS Databricks cross-account role ARN from the infra state."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^arn:(aws|aws-us-gov):iam::[0-9]{12}:role/.+$", var.cross_account_role_arn))
    error_message = "cross_account_role_arn must be an AWS IAM role ARN."
  }
}

variable "root_storage_bucket_name" {
  description = "S3 root-storage bucket name from the infra state."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.root_storage_bucket_name))
    error_message = "root_storage_bucket_name must be a valid lowercase S3 bucket name."
  }
}

variable "vpc_id" {
  description = "AWS VPC ID from the infra state."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID."
  }
}

variable "workspace_subnet_ids" {
  description = "At least two Databricks workspace subnet IDs from the infra state."
  type        = list(string)
  nullable    = false

  validation {
    condition     = alltrue([for subnet_id in var.workspace_subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet_id))])
    error_message = "Each workspace_subnet_ids item must be an AWS subnet ID."
  }
}

variable "workspace_security_group_id" {
  description = "Databricks workspace security group ID from the infra state."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.workspace_security_group_id))
    error_message = "workspace_security_group_id must be an AWS security group ID."
  }
}
