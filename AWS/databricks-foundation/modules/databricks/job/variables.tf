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
