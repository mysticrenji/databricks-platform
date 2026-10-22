mock_provider "databricks" {
  alias = "workspace"
}

variables {
  jobs = {
    "daily-ingestion" = {
      job_clusters = {
        ingestion = { spark_version = "auto:latest-lts", node_type_id = "m5d.large", policy_id = "policy-123" }
      }
      tasks = {
        ingest = { notebook_path = "/Shared/jobs/ingest", job_cluster_key = "ingestion" }
      }
      permissions = { groups = { "data-engineers" = "CAN_MANAGE_RUN" } }
    }
  }
}

run "creates_notebook_job_with_job_cluster" {
  command = plan
  assert {
    condition     = databricks_job.this["daily-ingestion"].name == "daily-ingestion"
    error_message = "The job must use its configured name."
  }
  assert {
    condition     = length(databricks_job.this["daily-ingestion"].task) == 1
    error_message = "The job must include the configured notebook task."
  }
  assert {
    condition     = length(databricks_permissions.job["daily-ingestion"].access_control) == 1
    error_message = "The job permission must be managed."
  }
}

run "creates_no_jobs_by_default" {
  command = plan
  variables { jobs = {} }
  assert {
    condition     = length(databricks_job.this) == 0
    error_message = "The module must not create jobs by default."
  }
}

run "rejects_task_without_compute" {
  command = plan
  variables { jobs = { invalid = { tasks = { task = { notebook_path = "/Shared/jobs/invalid" } } } } }
  expect_failures = [terraform_data.validation]
}
