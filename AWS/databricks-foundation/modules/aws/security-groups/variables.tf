variable "name" {
  description = "Name for the Databricks workspace security group."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty with no leading or trailing whitespace."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that owns the Databricks workspace security group."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "enable_privatelink" {
  description = "Allow TCP 6666 for secure cluster connectivity when classic PrivateLink is enabled."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_fips" {
  description = "Allow TCP 2443 when the Databricks compliance security profile with FIPS is enabled."
  type        = bool
  default     = false
  nullable    = false
}

variable "tags" {
  description = "Additional tags applied to the security group. The Name tag takes precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
