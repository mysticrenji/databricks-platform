locals {
  bucket_arn         = "arn:${var.aws_partition}:s3:::${var.bucket_name}"
  bucket_objects_arn = "arn:${var.aws_partition}:s3:::${var.bucket_name}/*"

  workspace_instance_profile_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "WorkspaceRootStorageObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"]
        Resource = local.bucket_objects_arn
      },
      {
        Sid      = "WorkspaceRootStorageBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = local.bucket_arn
      },
      ], var.kms_key_arn == null ? [] : [
      {
        Sid      = "WorkspaceRootStorageKms"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = var.kms_key_arn
        Condition = {
          StringEquals = {
            "kms:ViaService" = "s3.${var.aws_region}.amazonaws.com"
          }
        }
      },
    ])
  })

  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GrantDatabricksControlPlaneAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${var.aws_partition}:iam::${var.databricks_control_plane_account_id}:root"
        }
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = [local.bucket_arn, local.bucket_objects_arn]
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/DatabricksAccountId" = var.databricks_account_id
          }
        }
      },
      {
        Sid    = "DenyDbfsAccessToUnityCatalogPrefix"
        Effect = "Deny"
        Principal = {
          AWS = "arn:${var.aws_partition}:iam::${var.databricks_control_plane_account_id}:root"
        }
        Action   = "s3:*"
        Resource = "${local.bucket_arn}/unity-catalog/*"
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [local.bucket_arn, local.bucket_objects_arn]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket" "root" {
  bucket        = var.bucket_name
  force_destroy = false

  lifecycle {
    precondition {
      condition     = var.kms_key_arn == null || var.aws_region != null
      error_message = "aws_region is required when kms_key_arn is set."
    }
  }

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

resource "aws_s3_bucket_public_access_block" "root" {
  bucket = aws_s3_bucket.root.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "root" {
  bucket = aws_s3_bucket.root.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "root" {
  bucket = aws_s3_bucket.root.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "root" {
  bucket = aws_s3_bucket.root.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_policy" "root" {
  bucket = aws_s3_bucket.root.id
  policy = local.bucket_policy

  depends_on = [aws_s3_bucket_public_access_block.root]
}

resource "aws_iam_role_policy" "workspace_root_storage" {
  name   = "${var.name}-root-storage"
  role   = var.workspace_instance_profile_role_name
  policy = local.workspace_instance_profile_policy
}
