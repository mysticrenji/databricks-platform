data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  role_arns = { for key, bucket in var.buckets : key => "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-uc-${key}" }
}

resource "aws_iam_role" "this" {
  for_each = var.buckets
  name     = "${var.name}-uc-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid       = "SelfAssumption"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
      Condition = { ArnEquals = { "aws:PrincipalArn" = local.role_arns[each.key] } }
      }], contains(keys(var.trust), each.key) ? [{
      Sid       = "UnityCatalog"
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = var.trust[each.key].unity_catalog_iam_arn }
      Condition = { StringEquals = { "sts:ExternalId" = var.trust[each.key].external_id } }
    }] : [])
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  for_each = var.buckets
  name     = "unity-catalog-storage"
  role     = aws_iam_role.this[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads"]
        Resource = each.value.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"]
        Resource = "${each.value.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.role_arns[each.key]
      },
    ]
  })
}
