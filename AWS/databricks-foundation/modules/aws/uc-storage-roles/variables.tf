variable "name" {
  description = "Environment-specific IAM role prefix."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,40}$", var.name))
    error_message = "name must be 1-40 letters, numbers, underscores, or hyphens."
  }
}

variable "buckets" {
  description = "Dedicated data buckets keyed by landing, uc_managed, and optional observability."
  type        = map(object({ arn = string }))
  nullable    = false
  validation {
    condition     = alltrue([for key, bucket in var.buckets : contains(["landing", "uc_managed", "observability"], key) && can(regex("^arn:aws(-us-gov)?:s3:::[a-z0-9.-]+$", bucket.arn))])
    error_message = "Use landing, uc_managed, or observability keys with S3 bucket ARNs."
  }
}

variable "trust" {
  description = "Credential-generated trust details, passed directly from storage credentials in the data-access integration."
  type = map(object({
    external_id           = string
    unity_catalog_iam_arn = string
  }))
  default  = {}
  nullable = false
  validation {
    condition     = alltrue([for key, trust in var.trust : contains(keys(var.buckets), key) && length(trimspace(trust.external_id)) > 0 && can(regex("^arn:aws(-us-gov)?:iam::[0-9]{12}:role/.+$", trust.unity_catalog_iam_arn))])
    error_message = "Trust keys must match buckets and supply a nonempty external ID and Databricks IAM role ARN."
  }
}

variable "tags" {
  description = "Tags applied to the dedicated UC IAM roles."
  type        = map(string)
  default     = {}
  nullable    = false
}
