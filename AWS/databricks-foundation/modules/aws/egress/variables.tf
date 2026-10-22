variable "name" {
  description = "Prefix for names applied to egress resources."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty with no leading or trailing whitespace."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that owns the egress resources."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "nat_subnets" {
  description = "Public subnet definitions keyed by stable NAT gateway key. Each receives one zonal NAT gateway."
  type = map(object({
    availability_zone = string
    cidr_block        = string
    tags              = optional(map(string), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for subnet in values(var.nat_subnets) :
      try(
        cidrnetmask(subnet.cidr_block) != "" &&
        tonumber(split("/", subnet.cidr_block)[1]) >= 16 &&
        tonumber(split("/", subnet.cidr_block)[1]) <= 28 &&
        subnet.cidr_block == format("%s/%s", cidrhost(subnet.cidr_block, 0), split("/", subnet.cidr_block)[1]),
        false
      )
    ])
    error_message = "Each NAT subnet cidr_block must be a canonical IPv4 CIDR with a /16 through /28 prefix."
  }
}

variable "workspace_subnet_ids" {
  description = "Databricks workspace subnet IDs keyed by stable logical name."
  type        = map(string)
  nullable    = false
}

variable "workspace_subnet_nat_gateway_keys" {
  description = "Maps each workspace subnet key to the NAT gateway key in nat_subnets that provides its egress."
  type        = map(string)
  nullable    = false
}

variable "tags" {
  description = "Additional tags applied to all egress resources. Resource Name tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
