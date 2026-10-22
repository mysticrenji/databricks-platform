mock_provider "aws" {}

variables {
  name                                 = "databricks-dev-eu-central-1"
  bucket_name                          = "databricks-dev-eu-central-1-root-123456789012"
  workspace_instance_profile_role_name = "databricks-dev-eu-central-1-instance-profile"
  databricks_account_id                = "12345678-1234-1234-1234-123456789abc"
}

run "creates_a_private_versioned_encrypted_root_bucket" {
  command = plan

  assert {
    condition     = aws_s3_bucket_public_access_block.root.block_public_acls && aws_s3_bucket_public_access_block.root.block_public_policy && aws_s3_bucket_public_access_block.root.restrict_public_buckets
    error_message = "The workspace root bucket must block all public access."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.root.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "The workspace root bucket must disable ACLs with bucket-owner-enforced ownership."
  }

  assert {
    condition     = aws_s3_bucket_versioning.root.versioning_configuration[0].status == "Enabled"
    error_message = "The workspace root bucket must enable versioning."
  }

  assert {
    condition = alltrue([
      for rule in aws_s3_bucket_server_side_encryption_configuration.root.rule :
      rule.apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    ])
    error_message = "The workspace root bucket must use default server-side encryption."
  }
}

run "grants_databricks_control_plane_access_with_account_condition" {
  command = plan

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.root.policy).Statement[0].Condition.StringEquals["aws:PrincipalTag/DatabricksAccountId"] == "12345678-1234-1234-1234-123456789abc"
    error_message = "The bucket policy must constrain Databricks access to this Databricks account."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.root.policy).Statement[1].Sid == "DenyDbfsAccessToUnityCatalogPrefix"
    error_message = "The bucket policy must preserve the Unity Catalog prefix boundary."
  }
}

run "rejects_invalid_bucket_name" {
  command = plan
  variables {
    bucket_name = "Invalid_Bucket_Name"
  }
  expect_failures = [var.bucket_name]
}
