mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

variables {
  name    = "dev"
  buckets = { landing = { arn = "arn:aws:s3:::dev-landing" } }
}

run "bootstrap_has_no_databricks_access" {
  command = plan
  assert {
    condition     = length(jsondecode(aws_iam_role.this["landing"].assume_role_policy).Statement) == 1
    error_message = "Bootstrap must not allow Databricks to assume a role without an external ID."
  }
  assert {
    condition     = jsondecode(aws_iam_role_policy.this["landing"].policy).Statement[1].Resource == "arn:aws:s3:::dev-landing/*"
    error_message = "Object access must be restricted to the configured bucket."
  }
}

run "completed_trust_is_scoped_to_credential" {
  command = plan
  variables {
    trust = {
      landing = {
        external_id           = "credential-external-id"
        unity_catalog_iam_arn = "arn:aws:iam::414351767826:role/uc-test"
      }
    }
  }
  assert {
    condition     = jsondecode(aws_iam_role.this["landing"].assume_role_policy).Statement[1].Condition.StringEquals["sts:ExternalId"] == "credential-external-id"
    error_message = "UC trust must require the credential's exact external ID."
  }
  assert {
    condition     = jsondecode(aws_iam_role.this["landing"].assume_role_policy).Statement[0].Condition.ArnEquals["aws:PrincipalArn"] == "arn:aws:iam::123456789012:role/dev-uc-landing"
    error_message = "Self-assumption must be restricted to this role."
  }
}
