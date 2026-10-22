variable "name" {
  description = "VPC Name tag. Takes precedence over tags[\"Name\"]."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty with no leading or trailing whitespace."
  }
}

variable "cidr_block" {
  description = "Canonical RFC 1918 IPv4 CIDR, /16 through /25, sized for the future Databricks subnets."
  type        = string
  nullable    = false

  validation {
    condition = try(
      cidrnetmask(var.cidr_block) != "" &&
      tonumber(split("/", var.cidr_block)[1]) >= 16 &&
      tonumber(split("/", var.cidr_block)[1]) <= 25 &&
      var.cidr_block == format("%s/%s", cidrhost(var.cidr_block, 0), split("/", var.cidr_block)[1]),
      false
    )
    error_message = "cidr_block must be a canonical IPv4 CIDR between /16 and /25 (for example, 10.20.0.0/16). /25 is the minimum for two Databricks /26 subnets; allow more space for NAT and endpoint subnets."
  }

  validation {
    condition = try(
      split(".", cidrhost(var.cidr_block, 0))[0] == "10" ||
      (split(".", cidrhost(var.cidr_block, 0))[0] == "172" &&
        tonumber(split(".", cidrhost(var.cidr_block, 0))[1]) >= 16 &&
      tonumber(split(".", cidrhost(var.cidr_block, 0))[1]) <= 31) ||
      (split(".", cidrhost(var.cidr_block, 0))[0] == "192" &&
      split(".", cidrhost(var.cidr_block, 0))[1] == "168"),
      false
    )
    error_message = "cidr_block must be within private RFC 1918 space: 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16."
  }
}

variable "tags" {
  description = "Additional VPC tags. Organization-wide tags can also be set with provider default_tags."
  type        = map(string)
  default     = {}
  nullable    = false
}
