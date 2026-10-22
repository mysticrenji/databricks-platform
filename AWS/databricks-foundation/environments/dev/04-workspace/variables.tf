variable "state_bucket" {
  description = "Existing S3 bucket containing the development phase states."
  type        = string
  nullable    = false
}

variable "state_region" {
  description = "AWS Region of the S3 state bucket."
  type        = string
  nullable    = false
}

variable "infra_state_key" {
  description = "S3 key written by 01-infra."
  type        = string
  nullable    = false
  default     = "databricks/dev/shared/01-infra.tfstate"
}

variable "account_state_key" {
  description = "S3 key written by 02-account."
  type        = string
  nullable    = false
  default     = "databricks/dev/shared/02-account.tfstate"
}

variable "groups" {
  description = "Workspace-local groups to create, keyed by display name. Keep compute and SQL entitlements disabled unless a group requires them."
  type = map(object({
    workspace_access           = optional(bool, true)
    workspace_consume          = optional(bool)
    databricks_sql_access      = optional(bool, false)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.groups) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each group name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for group in values(var.groups) : !(group.workspace_access && group.workspace_consume == true)])
    error_message = "workspace_access and workspace_consume cannot both be enabled for a group."
  }
}

variable "service_principals" {
  description = "Workspace-local automation service principals to create, keyed by display name. Prefer account-level service principals with identity federation where available."
  type = map(object({
    active                     = optional(bool, true)
    workspace_access           = optional(bool, true)
    workspace_consume          = optional(bool)
    databricks_sql_access      = optional(bool, false)
    allow_cluster_create       = optional(bool, false)
    allow_instance_pool_create = optional(bool, false)
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.service_principals) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each service principal name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition     = alltrue([for service_principal in values(var.service_principals) : !(service_principal.workspace_access && service_principal.workspace_consume == true)])
    error_message = "workspace_access and workspace_consume cannot both be enabled for a service principal."
  }
}

variable "cluster_log_volume_path" {
  description = "Optional existing UC volume path enforced for logging on all configured compute policies. Create the volume before applying."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.cluster_log_volume_path == null || can(regex("^/Volumes/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*(/.*)?$", var.cluster_log_volume_path))
    error_message = "Use an absolute /Volumes/catalog/schema/volume path."
  }
}

variable "cluster_policies" {
  description = "Cluster policies keyed by display name. Define a policy JSON object or a policy family and overrides, with optional authoritative permissions."
  type = map(object({
    description                        = optional(string)
    definition                         = optional(any)
    policy_family_id                   = optional(string)
    policy_family_definition_overrides = optional(any)
    max_clusters_per_user              = optional(number)
    permissions = optional(object({
      groups             = optional(map(string), {})
      service_principals = optional(map(string), {})
      users              = optional(map(string), {})
    }), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for name in keys(var.cluster_policies) : length(trimspace(name)) > 0 && name == trimspace(name) && length(name) <= 255])
    error_message = "Each cluster policy name must be non-empty, have no leading or trailing whitespace, and be at most 255 characters."
  }

  validation {
    condition = alltrue(flatten([
      for policy in values(var.cluster_policies) : [
        policy.max_clusters_per_user == null ? true : (policy.max_clusters_per_user > 0 && floor(policy.max_clusters_per_user) == policy.max_clusters_per_user),
        alltrue([for level in values(policy.permissions.groups) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(policy.permissions.service_principals) : contains(["CAN_USE", "CAN_MANAGE"], level)]),
        alltrue([for level in values(policy.permissions.users) : contains(["CAN_USE", "CAN_MANAGE"], level)])
      ]
    ]))
    error_message = "max_clusters_per_user must be a positive whole number, and cluster policy permissions must be CAN_USE or CAN_MANAGE."
  }
}

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

variable "jobs" {
  description = "Notebook jobs keyed by name, with ephemeral job clusters or approved existing clusters, schedules, and authoritative permissions."
  type = map(object({
    description         = optional(string)
    max_concurrent_runs = optional(number, 1)
    timeout_seconds     = optional(number, 0)
    tags                = optional(map(string), {})
    email_on_failure    = optional(set(string), [])
    schedule = optional(object({
      quartz_cron_expression = string
      timezone_id            = string
      pause_status           = optional(string, "UNPAUSED")
    }))
    job_clusters = optional(map(object({
      spark_version      = string
      node_type_id       = string
      num_workers        = optional(number, 1)
      policy_id          = optional(string)
      data_security_mode = optional(string)
    })), {})
    tasks = map(object({
      notebook_path       = string
      source              = optional(string)
      base_parameters     = optional(map(string), {})
      existing_cluster_id = optional(string)
      job_cluster_key     = optional(string)
      depends_on          = optional(set(string), [])
      timeout_seconds     = optional(number, 0)
      max_retries         = optional(number, 1)
      retry_on_timeout    = optional(bool, false)
    }))
    permissions = optional(object({
      groups             = optional(map(string), {})
      service_principals = optional(map(string), {})
      users              = optional(map(string), {})
    }), {})
  }))
  nullable = false
  default  = {}

  validation {
    condition = alltrue(flatten([
      for name, job in var.jobs : [
        length(trimspace(name)) > 0 && name == trimspace(name),
        length(job.tasks) > 0,
        job.max_concurrent_runs > 0,
        alltrue([for key, task in job.tasks : length(trimspace(key)) > 0 && length(trimspace(task.notebook_path)) > 0]),
        alltrue([for level in values(job.permissions.groups) : contains(["CAN_VIEW", "CAN_MANAGE_RUN", "IS_OWNER", "CAN_MANAGE"], level)]),
        alltrue([for level in values(job.permissions.service_principals) : contains(["CAN_VIEW", "CAN_MANAGE_RUN", "IS_OWNER", "CAN_MANAGE"], level)]),
        alltrue([for level in values(job.permissions.users) : contains(["CAN_VIEW", "CAN_MANAGE_RUN", "IS_OWNER", "CAN_MANAGE"], level)])
      ]
    ]))
    error_message = "Jobs need a name, at least one notebook task, positive concurrency, and valid job permission levels."
  }
}

variable "register_infra_instance_profile" {
  description = "Register the compute instance profile created in phase one."
  type        = bool
  nullable    = false
  default     = false
}

variable "instance_profile_group_names" {
  description = "Bootstrap group names explicitly permitted to use the infra instance profile."
  type        = set(string)
  nullable    = false
  default     = []
}

variable "init_script_volume_path" {
  description = "Optional existing UC shell script fixed at init-script index zero on all configured compute policies."
  type        = string
  default     = null
  nullable    = true
  validation {
    condition     = var.init_script_volume_path == null || can(regex("^/Volumes/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[a-z][a-z0-9_]*/[^\\r\\n]+\\.sh$", var.init_script_volume_path))
    error_message = "Use an absolute /Volumes/catalog/schema/volume/script.sh path."
  }
}

variable "enable_hello_world_init_script" {
  description = "Upload the bundled hello-world script to init_script_volume_path before configuring compute policies. The UC volume must already exist."
  type        = bool
  default     = false
  nullable    = false
}

variable "data_access_state_key" {
  description = "S3 key written by 03-data-access; apply it before workspace compute configuration."
  type        = string
  nullable    = false
  default     = "databricks/dev/shared/03-data-access.tfstate"
}

variable "read_data_access_state" {
  description = "Read root 03 outputs for legacy workspace configuration. Disable only for compute without UC volume logging or init scripts."
  type        = bool
  nullable    = false
  default     = true

  validation {
    condition = var.read_data_access_state || (
      var.cluster_log_volume_path == null &&
      var.init_script_volume_path == null &&
      !var.enable_hello_world_init_script
    )
    error_message = "Root 03 may be skipped only with null log/init-script paths and the hello-world upload disabled."
  }
}

variable "compute_identity" {
  description = "Optional verified identity for the dev/demo persona compute runner; legacy callers leave this null."
  type = object({
    environment   = string
    workspace     = string
    account_id    = string
    workspace_id  = string
    workspace_url = string
  })
  nullable = true
  default  = null

  validation {
    condition = var.compute_identity == null ? true : (
      var.compute_identity.environment == "dev" &&
      var.compute_identity.workspace == "demo" &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.compute_identity.account_id)) &&
      can(regex("^[1-9][0-9]*$", var.compute_identity.workspace_id)) &&
      can(regex("^https://[a-z0-9][a-z0-9-]*[.]cloud[.]databricks[.]com$", var.compute_identity.workspace_url))
    )
    error_message = "Generated compute supports only dev/demo, a UUID account ID, positive numeric workspace ID, and HTTPS AWS Databricks workspace URL."
  }
}

variable "compute_group_ids" {
  description = "Existing account group IDs keyed by display name, verified against the root 02 outputs. No groups or memberships are created."
  type        = map(string)
  nullable    = false
  default     = {}

  validation {
    condition = alltrue([
      for name, id in var.compute_group_ids :
      length(trimspace(name)) > 0 && name == trimspace(name) && can(regex("^[1-9][0-9]*$", id))
    ])
    error_message = "Compute groups require nonempty trimmed names and positive numeric SCIM IDs."
  }
}
