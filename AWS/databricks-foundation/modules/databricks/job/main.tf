locals {
  jobs_with_permissions = {
    for name, job in var.jobs : name => job
    if length(job.permissions.groups) + length(job.permissions.service_principals) + length(job.permissions.users) > 0
  }
}

resource "terraform_data" "validation" {
  input = var.jobs

  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for job in values(var.jobs) : [
          for task in values(job.tasks) : (task.existing_cluster_id == null) != (task.job_cluster_key == null) && (task.job_cluster_key == null || contains(keys(job.job_clusters), task.job_cluster_key))
        ]
      ]))
      error_message = "Each task must set exactly one compute target, and job_cluster_key must refer to a declared job cluster."
    }
  }
}

resource "databricks_job" "this" {
  provider = databricks.workspace
  for_each = var.jobs

  name                = each.key
  description         = each.value.description
  max_concurrent_runs = each.value.max_concurrent_runs
  timeout_seconds     = each.value.timeout_seconds
  tags                = each.value.tags

  dynamic "job_cluster" {
    for_each = each.value.job_clusters

    content {
      job_cluster_key = job_cluster.key

      new_cluster {
        spark_version      = job_cluster.value.spark_version
        node_type_id       = job_cluster.value.node_type_id
        num_workers        = job_cluster.value.num_workers
        policy_id          = job_cluster.value.policy_id
        data_security_mode = job_cluster.value.data_security_mode
      }
    }
  }

  dynamic "task" {
    for_each = each.value.tasks

    content {
      task_key            = task.key
      existing_cluster_id = task.value.existing_cluster_id
      job_cluster_key     = task.value.job_cluster_key
      timeout_seconds     = task.value.timeout_seconds
      max_retries         = task.value.max_retries
      retry_on_timeout    = task.value.retry_on_timeout

      notebook_task {
        notebook_path   = task.value.notebook_path
        source          = task.value.source
        base_parameters = task.value.base_parameters
      }

      dynamic "depends_on" {
        for_each = task.value.depends_on

        content {
          task_key = depends_on.value
        }
      }
    }
  }

  dynamic "schedule" {
    for_each = each.value.schedule == null ? [] : [each.value.schedule]

    content {
      quartz_cron_expression = schedule.value.quartz_cron_expression
      timezone_id            = schedule.value.timezone_id
      pause_status           = schedule.value.pause_status
    }
  }

  dynamic "email_notifications" {
    for_each = length(each.value.email_on_failure) > 0 ? [each.value.email_on_failure] : []

    content {
      on_failure = email_notifications.value
    }
  }

  depends_on = [terraform_data.validation]
}

resource "databricks_permissions" "job" {
  provider = databricks.workspace
  for_each = local.jobs_with_permissions

  job_id = databricks_job.this[each.key].id

  dynamic "access_control" {
    for_each = each.value.permissions.groups
    content {
      group_name       = access_control.key
      permission_level = access_control.value
    }
  }
  dynamic "access_control" {
    for_each = each.value.permissions.service_principals
    content {
      service_principal_name = access_control.key
      permission_level       = access_control.value
    }
  }
  dynamic "access_control" {
    for_each = each.value.permissions.users
    content {
      user_name        = access_control.key
      permission_level = access_control.value
    }
  }
}
