variable "name" {
  description = "Lowercase bucket-name prefix, normally including project, environment, and region."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,37}[a-z0-9]$", var.name))
    error_message = "name must be 2-39 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
  }
}

variable "enable_observability_bucket" {
  description = "Create an additional private bucket for Unity Catalog managed operational data and cluster logs."
  type        = bool
  default     = false
  nullable    = false
}

variable "observability_bucket_name" {
  description = "Optional globally unique logs bucket name; null generates <name>-logs-<AWS account ID>."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.observability_bucket_name == null || can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.observability_bucket_name))
    error_message = "Use a 3-63 character lowercase bucket name containing letters, digits, or hyphens."
  }
}

variable "tags" {
  description = "Additional bucket tags. Name and Purpose take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
