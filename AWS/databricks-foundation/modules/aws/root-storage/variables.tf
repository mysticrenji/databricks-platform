variable "name" {
  description = "Prefix for the workspace root-storage IAM policy."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name) && length(var.name) <= 100
    error_message = "name must be non-empty, have no leading or trailing whitespace, and be at most 100 characters."
  }
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name for Databricks workspace root storage."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name)) && !can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.bucket_name))
    error_message = "bucket_name must be a 3-63 character lowercase S3 bucket name and must not be formatted as an IPv4 address."
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

variable "kms_key_arn" {
  description = "Optional customer-managed KMS key ARN for SSE-KMS. Null keeps the default SSE-S3 encryption."
  type        = string
  default     = null
  nullable    = true
}

variable "aws_region" {
  description = "AWS region of the root storage bucket. Required only when kms_key_arn is set."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.aws_region == null || can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be null or a valid AWS region identifier."
  }
}

variable "databricks_account_id" {
  description = "Databricks account ID required by the Databricks control-plane bucket-policy condition."
  type        = string
  nullable    = false
  sensitive   = true

  validation {
    condition     = length(trimspace(var.databricks_account_id)) > 0 && var.databricks_account_id == trimspace(var.databricks_account_id)
    error_message = "databricks_account_id must be non-empty with no leading or trailing whitespace."
  }
}

variable "databricks_control_plane_account_id" {
  description = "Databricks AWS control-plane account granted root-storage bucket access."
  type        = string
  default     = "414351767826"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{12}$", var.databricks_control_plane_account_id))
    error_message = "databricks_control_plane_account_id must be a 12-digit AWS account ID."
  }
}

variable "aws_partition" {
  description = "AWS partition used in S3 and IAM ARNs, for example aws or aws-us-gov."
  type        = string
  default     = "aws"
  nullable    = false

  validation {
    condition     = contains(["aws", "aws-us-gov"], var.aws_partition)
    error_message = "aws_partition must be aws or aws-us-gov."
  }
}

variable "tags" {
  description = "Additional tags applied to the root bucket. The Name tag takes precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
