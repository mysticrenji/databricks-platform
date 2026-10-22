# Databricks jobs

Creates notebook-based Databricks jobs with ephemeral job clusters or approved
existing clusters, schedules, failure notifications, and explicit permissions.
It uses the workspace-level provider alias, `databricks.workspace`.

```hcl
module "job" {
  source = "./modules/databricks/job"
  providers = { databricks.workspace = databricks.workspace }

  jobs = {
    "daily-ingestion" = {
      max_concurrent_runs = 1
      schedule = {
        quartz_cron_expression = "0 0 6 * * ?"
        timezone_id            = "Europe/Amsterdam"
      }
      job_clusters = {
        ingestion = {
          spark_version = "auto:latest-lts"
          node_type_id  = "m5d.large"
          policy_id     = module.cluster_policies.cluster_policy_ids["shared-engineering"]
        }
      }
      tasks = {
        ingest = {
          notebook_path   = "/Shared/jobs/ingest"
          job_cluster_key = "ingestion"
        }
      }
      permissions = { groups = { "data-engineers" = "CAN_MANAGE_RUN" } }
    }
  }
}
```

Each task must specify exactly one of `job_cluster_key` or
`existing_cluster_id`. Prefer ephemeral job clusters governed by a cluster
policy. This module supports notebook tasks; use a dedicated module when a
workload needs a different Databricks task type.

Permissions are authoritative when configured for a job. Job permissions govern
run and management access; Unity Catalog grants govern the data a job can use.

## Outputs

- `job_ids`
- `job_urls`
