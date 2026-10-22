mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }
}

run "isolates_and_protects_data_buckets" {
  command = plan
  variables {
    name = "databricks-dev-eu-west-1"
  }
  assert {
    condition     = aws_s3_bucket.this["landing"].bucket == "databricks-dev-eu-west-1-landing-123456789012" && aws_s3_bucket.this["uc_managed"].bucket == "databricks-dev-eu-west-1-uc-managed-123456789012"
    error_message = "Landing and managed storage must use distinct account-specific names."
  }
  assert {
    condition     = alltrue([for bucket in aws_s3_bucket.this : !bucket.force_destroy]) && alltrue([for block in aws_s3_bucket_public_access_block.this : block.block_public_acls && block.block_public_policy && block.ignore_public_acls && block.restrict_public_buckets])
    error_message = "Both buckets must block public access and reject forced deletion of contents."
  }
  assert {
    condition     = alltrue([for versioning in aws_s3_bucket_versioning.this : one(versioning.versioning_configuration).status == "Enabled"])
    error_message = "Both buckets must preserve object versions."
  }
}
run "adds_dedicated_logs_without_renaming_existing_buckets" {
  command = plan
  variables {
    name                        = "databricks-dev-eu-west-1"
    enable_observability_bucket = true
  }
  assert {
    condition     = length(aws_s3_bucket.this) == 3 && aws_s3_bucket.this["observability"].bucket == "databricks-dev-eu-west-1-logs-123456789012" && aws_s3_bucket.this["uc_managed"].bucket == "databricks-dev-eu-west-1-uc-managed-123456789012"
    error_message = "The optional log bucket must be added without changing existing managed storage."
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.this["observability"].block_public_policy && !aws_s3_bucket.this["observability"].force_destroy
    error_message = "Logs must be private and protected from forced deletion."
  }
}

run "supports_explicit_logs_bucket_name" {
  command = plan
  variables {
    name                        = "dev"
    enable_observability_bucket = true
    observability_bucket_name   = "company-dev-observability-123456789012"
  }
  assert {
    condition     = aws_s3_bucket.this["observability"].bucket == "company-dev-observability-123456789012"
    error_message = "An explicit log bucket name must be respected."
  }
}
