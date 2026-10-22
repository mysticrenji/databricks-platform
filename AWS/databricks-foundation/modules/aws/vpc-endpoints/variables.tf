variable "name" {
  description = "Prefix for VPC endpoint resource names."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty with no leading or trailing whitespace."
  }
}

variable "aws_region" {
  description = "AWS region that hosts the VPC and AWS service endpoints."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier, for example eu-central-1."
  }
}

variable "vpc_id" {
  description = "ID of the VPC that owns these endpoints."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be an AWS VPC ID, for example vpc-0123456789abcdef0."
  }
}

variable "workspace_security_group_id" {
  description = "Databricks workspace security group allowed to reach the interface endpoints over HTTPS."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.workspace_security_group_id))
    error_message = "workspace_security_group_id must be an AWS security group ID, for example sg-0123456789abcdef0."
  }
}

variable "endpoint_subnets" {
  description = "Dedicated private subnet definitions for interface endpoint network interfaces, keyed by stable logical name."
  type = map(object({
    availability_zone = string
    cidr_block        = string
    tags              = optional(map(string), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for subnet in values(var.endpoint_subnets) :
      try(
        cidrnetmask(subnet.cidr_block) != "" &&
        tonumber(split("/", subnet.cidr_block)[1]) >= 17 &&
        tonumber(split("/", subnet.cidr_block)[1]) <= 27 &&
        subnet.cidr_block == format("%s/%s", cidrhost(subnet.cidr_block, 0), split("/", subnet.cidr_block)[1]),
        false
      )
    ])
    error_message = "Each endpoint subnet cidr_block must be a canonical IPv4 CIDR with a /17 through /27 prefix."
  }
}

variable "workspace_route_table_ids" {
  description = "Private workspace route table IDs for the S3 gateway endpoint, keyed by stable logical name."
  type        = map(string)
  nullable    = false
}

variable "tags" {
  description = "Additional tags applied to endpoint resources. Resource Name tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}
