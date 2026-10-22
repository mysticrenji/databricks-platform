variable "name" {
  description = "Prefix for the Name tag of each workspace subnet."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty with no leading or trailing whitespace."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that owns the workspace subnets."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "workspace_subnets" {
  description = "Databricks workspace subnet definitions keyed by a stable logical name. Each subnet is private and must be in a unique availability zone."
  type = map(object({
    availability_zone = string
    cidr_block        = string
    tags              = optional(map(string), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for subnet in values(var.workspace_subnets) :
      try(
        cidrnetmask(subnet.cidr_block) != "" &&
        tonumber(split("/", subnet.cidr_block)[1]) >= 17 &&
        tonumber(split("/", subnet.cidr_block)[1]) <= 26 &&
        subnet.cidr_block == format("%s/%s", cidrhost(subnet.cidr_block, 0), split("/", subnet.cidr_block)[1]),
        false
      )
    ])
    error_message = "Each workspace subnet cidr_block must be a canonical IPv4 CIDR with a /17 through /26 prefix."
  }
}

variable "tags" {
  description = "Additional tags applied to every workspace subnet. Per-subnet tags take precedence, except Name."
  type        = map(string)
  default     = {}
  nullable    = false
}
