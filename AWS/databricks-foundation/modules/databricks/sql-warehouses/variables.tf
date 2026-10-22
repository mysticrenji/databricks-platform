variable "warehouses" {
  description = "SQL warehouses keyed by name, with bounded capacity, optional tags, and authoritative access permissions."
  type = map(object({
    cluster_size              = optional(string, "Small")
    auto_stop_mins            = optional(number, 10)
    min_num_clusters          = optional(number, 1)
    max_num_clusters          = optional(number, 1)
    enable_photon             = optional(bool, true)
    enable_serverless_compute = optional(bool, false)
    warehouse_type            = optional(string)
    spot_instance_policy      = optional(string)
    tags                      = optional(map(string), {})
    permissions = optional(object({
      groups             = optional(map(string), {})
      service_principals = optional(map(string), {})
      users              = optional(map(string), {})
    }), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.warehouses) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each warehouse name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition = alltrue(flatten([
      for warehouse in values(var.warehouses) : [
        length(trimspace(warehouse.cluster_size)) > 0 && warehouse.cluster_size == trimspace(warehouse.cluster_size),
        warehouse.auto_stop_mins > 0 && floor(warehouse.auto_stop_mins) == warehouse.auto_stop_mins,
        warehouse.min_num_clusters > 0 && floor(warehouse.min_num_clusters) == warehouse.min_num_clusters,
        warehouse.max_num_clusters > 0 && floor(warehouse.max_num_clusters) == warehouse.max_num_clusters,
        alltrue([for level in values(warehouse.permissions.groups) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(warehouse.permissions.service_principals) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(warehouse.permissions.users) : contains(["CAN_USE", "CAN_MANAGE"], level)])
      ]
    ]))
    error_message = "Warehouse capacity values must be positive whole numbers, and permissions must be CAN_USE or CAN_MANAGE."
  }
}
