variable "grants" {
  description = "Unioned privileges keyed by a stable object/principal identity; objects must already exist."
  type = map(object({
    object_type = string
    object_name = string
    principal   = string
    privileges  = set(string)
  }))
  default  = {}
  nullable = false
  validation {
    condition = alltrue([for grant in values(var.grants) :
      contains(["catalog", "schema", "table"], grant.object_type) &&
      can(regex("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*){0,2}$", grant.object_name)) &&
      length(split(".", grant.object_name)) == lookup({ catalog = 1, schema = 2, table = 3 }, grant.object_type, 0) &&
      length(trimspace(grant.principal)) > 0 && !strcontains(grant.principal, "*") &&
      length(grant.privileges) > 0 && alltrue([for privilege in grant.privileges : contains(
        lookup({ catalog = ["USE_CATALOG"], schema = ["USE_SCHEMA", "SELECT", "MODIFY", "CREATE_TABLE"], table = ["SELECT", "MODIFY"] }, grant.object_type, []), privilege
      )])
    ]) && length(distinct([for grant in values(var.grants) : jsonencode([grant.object_type, grant.object_name, grant.principal])])) == length(var.grants)
    error_message = "Grants need unique object/principal pairs, simple existing object names, and supported reader/writer privileges; ownership/admin privileges are forbidden."
  }
}
