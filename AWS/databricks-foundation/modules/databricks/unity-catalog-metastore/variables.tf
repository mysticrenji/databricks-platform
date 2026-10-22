variable "metastore_name" {
  description = "Name of the Unity Catalog metastore. Use one metastore per AWS Region unless an exception is documented."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.metastore_name)) > 0 && var.metastore_name == trimspace(var.metastore_name) && length(var.metastore_name) <= 255
    error_message = "metastore_name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }
}

variable "aws_region" {
  description = "AWS Region for the metastore. It must match the assigned workspace region."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be an AWS Region identifier, such as eu-central-1."
  }
}

variable "workspace_id" {
  description = "Numeric Databricks workspace ID to assign to this metastore."
  type        = number
  nullable    = false

  validation {
    condition     = var.workspace_id > 0 && floor(var.workspace_id) == var.workspace_id
    error_message = "workspace_id must be a positive whole number."
  }
}

variable "owner" {
  description = "Optional metastore owner: a Databricks group name, user name, or service principal application ID."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.owner == null || (length(trimspace(var.owner)) > 0 && var.owner == trimspace(var.owner))
    error_message = "owner must be null or a non-empty value with no leading or trailing whitespace."
  }
}

variable "storage_root" {
  description = "Optional S3 path for metastore-level managed storage, for example s3://company-uc-dev/metastore. Prefer catalog-level managed locations when isolation between catalogs is required."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.storage_root == null || can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", var.storage_root))
    error_message = "storage_root must be null or a valid s3:// bucket path."
  }
}

variable "storage_root_credential_id" {
  description = "Optional existing Unity Catalog storage credential ID for storage_root. It must be provided whenever storage_root is set."
  type        = string
  nullable    = true
  default     = null

  validation {
    condition     = var.storage_root_credential_id == null || (length(trimspace(var.storage_root_credential_id)) > 0 && var.storage_root_credential_id == trimspace(var.storage_root_credential_id))
    error_message = "storage_root_credential_id must be null or a non-empty value with no leading or trailing whitespace."
  }
}
