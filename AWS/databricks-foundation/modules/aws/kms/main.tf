resource "terraform_data" "validation" {
  input = {
    aws_account_id                       = var.aws_account_id
    cross_account_role_name              = var.cross_account_role_name
    workspace_instance_profile_role_name = var.workspace_instance_profile_role_name
  }

  lifecycle {
    precondition {
      condition = !var.enabled || (
        var.aws_account_id != null &&
        var.cross_account_role_name != null &&
        var.workspace_instance_profile_role_name != null
      )
      error_message = "When enabled is true, aws_account_id, cross_account_role_name, and workspace_instance_profile_role_name are required."
    }
  }
}

locals {
  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableIamPoliciesInOwningAccount"
        Effect    = "Allow"
        Principal = { AWS = "arn:${var.aws_partition}:iam::${coalesce(var.aws_account_id, "000000000000")}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "AllowUseThroughS3InOwningAccount"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:DescribeKey",
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = coalesce(var.aws_account_id, "000000000000")
            "kms:ViaService"    = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ]
  })

  workspace_kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "UseRootStorageKeyThroughS3"
      Effect   = "Allow"
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
      Resource = try(aws_kms_key.workspace[0].arn, "")
      Condition = {
        StringEquals = {
          "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_kms_key" "workspace" {
  count = var.enabled ? 1 : 0

  description             = "Databricks workspace root-storage key"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = local.key_policy

  tags = merge(var.tags, {
    Name = "${var.name}-root-storage"
  })

  depends_on = [terraform_data.validation]
}

resource "aws_kms_alias" "workspace" {
  count = var.enabled ? 1 : 0

  name          = "alias/${var.name}-root-storage"
  target_key_id = aws_kms_key.workspace[0].key_id
}

resource "aws_iam_role_policy" "cross_account_kms" {
  count = var.enabled ? 1 : 0

  name   = "${var.name}-root-storage-kms"
  role   = var.cross_account_role_name
  policy = local.workspace_kms_policy
}

resource "aws_iam_role_policy" "instance_profile_kms" {
  count = var.enabled ? 1 : 0

  name   = "${var.name}-root-storage-kms"
  role   = var.workspace_instance_profile_role_name
  policy = local.workspace_kms_policy
}
