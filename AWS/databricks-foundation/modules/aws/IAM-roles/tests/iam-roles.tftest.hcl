mock_provider "aws" {}

variables {
  name                     = "databricks-dev-eu-central-1"
  databricks_account_id    = "12345678-1234-1234-1234-123456789abc"
  permissions_boundary_arn = "arn:aws:iam::123456789012:policy/DatabricksBoundary"
}

run "creates_databricks_cross_account_and_ec2_roles" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.databricks_cross_account.assume_role_policy).Statement[0].Condition.StringEquals["sts:ExternalId"] == "12345678-1234-1234-1234-123456789abc"
    error_message = "Cross-account trust must require the Databricks account ID as its external ID."
  }

  assert {
    condition     = jsondecode(aws_iam_role.databricks_cross_account.assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::414351767826:root"
    error_message = "Cross-account trust must allow the Databricks commercial control plane."
  }

  assert {
    condition     = jsondecode(aws_iam_role.workspace_instance_profile.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "The workspace instance profile role must be assumable by EC2."
  }

  assert {
    condition     = aws_iam_role.workspace_instance_profile.permissions_boundary == "arn:aws:iam::123456789012:policy/DatabricksBoundary"
    error_message = "The optional permissions boundary must apply to the workspace role."
  }

  assert {
    condition     = local.databricks_pass_compute_instance_profile_statement.Action == "iam:PassRole" && local.databricks_pass_compute_instance_profile_statement.Condition.StringEquals["iam:PassedToService"] == "ec2.amazonaws.com"
    error_message = "The cross-account role must only pass the compute role to EC2."
  }
}

run "supports_govcloud_partition" {
  command = plan
  variables {
    aws_partition                       = "aws-us-gov"
    databricks_control_plane_account_id = "044793339203"
  }

  assert {
    condition     = jsondecode(aws_iam_role.databricks_cross_account.assume_role_policy).Statement[0].Principal.AWS == "arn:aws-us-gov:iam::044793339203:root"
    error_message = "GovCloud must use its partition and control-plane account in the trust policy."
  }
}
