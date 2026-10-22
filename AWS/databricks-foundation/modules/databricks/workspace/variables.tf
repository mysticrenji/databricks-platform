variable "databricks_account_id" {
  description = "Databricks account ID that owns the workspace."
  type        = string
  nullable    = false
  sensitive   = true

  validation {
    condition     = length(trimspace(var.databricks_account_id)) > 0 && var.databricks_account_id == trimspace(var.databricks_account_id)
    error_message = "databricks_account_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "workspace_name" {
  description = "Display name for the Databricks workspace."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.workspace_name)) > 0 && var.workspace_name == trimspace(var.workspace_name) && length(var.workspace_name) <= 255
    error_message = "workspace_name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }
}

variable "aws_region" {
  description = "AWS Region in which to create the workspace. It must match the registered network and root-storage bucket region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be an AWS Region identifier, such as eu-central-1."
  }
}

variable "credentials_id" {
  description = "Databricks cross-account credential configuration ID from the account-configuration module."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.credentials_id)) > 0 && var.credentials_id == trimspace(var.credentials_id)
    error_message = "credentials_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "storage_configuration_id" {
  description = "Databricks root storage configuration ID from the account-configuration module."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.storage_configuration_id)) > 0 && var.storage_configuration_id == trimspace(var.storage_configuration_id)
    error_message = "storage_configuration_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "network_id" {
  description = "Databricks customer-managed network configuration ID from the account-configuration module."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.network_id)) > 0 && var.network_id == trimspace(var.network_id)
    error_message = "network_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "pricing_tier" {
  description = "Databricks workspace pricing tier. Use ENTERPRISE when the workspace requires Enterprise-only capabilities such as private connectivity features."
  type        = string
  nullable    = false
  default     = "PREMIUM"

  validation {
    condition     = contains(["PREMIUM", "ENTERPRISE"], var.pricing_tier)
    error_message = "pricing_tier must be PREMIUM or ENTERPRISE."
  }
}
