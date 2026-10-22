variable "external_locations" {
  description = "Unity Catalog external locations keyed by their Databricks name. Each location references an existing storage credential and may define authoritative grants."
  type = map(object({
    url                = string
    credential_name    = string
    owner              = optional(string)
    comment            = optional(string)
    read_only          = optional(bool, false)
    enable_file_events = optional(bool, false)
    skip_validation    = optional(bool, false)
    grants             = optional(map(set(string)), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.external_locations) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each external location name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for location in values(var.external_locations) : can(regex("^s3://[a-z0-9][a-z0-9.-]{1,61}[a-z0-9](/.*)?$", location.url))])
    error_message = "Each external location url must be a valid s3:// bucket path."
  }

  validation {
    condition     = length(distinct([for location in values(var.external_locations) : location.url])) == length(var.external_locations)
    error_message = "Each external location must use a distinct S3 URL."
  }

  validation {
    condition     = alltrue([for location in values(var.external_locations) : length(trimspace(location.credential_name)) > 0 && location.credential_name == trimspace(location.credential_name)])
    error_message = "Each credential_name must be non-empty with no leading or trailing whitespace."
  }

  validation {
    condition = alltrue(flatten([
      for location in values(var.external_locations) : [
        for principal, privileges in location.grants : length(trimspace(principal)) > 0 && principal == trimspace(principal) && length(privileges) > 0 && alltrue([for privilege in privileges : length(trimspace(privilege)) > 0 && privilege == trimspace(privilege)])
      ]
    ]))
    error_message = "Each grant must have a non-empty principal and at least one non-empty privilege."
  }
}
