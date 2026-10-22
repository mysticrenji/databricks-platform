data "aws_caller_identity" "current" {}

locals {
  bucket_names = merge({
    landing    = "${var.name}-landing-${data.aws_caller_identity.current.account_id}"
    uc_managed = "${var.name}-uc-managed-${data.aws_caller_identity.current.account_id}"
    }, var.enable_observability_bucket ? {
    observability = coalesce(var.observability_bucket_name, "${var.name}-logs-${data.aws_caller_identity.current.account_id}")
  } : {})
}

resource "aws_s3_bucket" "this" {
  for_each      = local.bucket_names
  bucket        = each.value
  force_destroy = false
  tags          = merge(var.tags, { Name = each.value, Purpose = each.key })
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = local.bucket_names
  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.bucket_names
  bucket   = aws_s3_bucket.this[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.this[each.key].arn, "${aws_s3_bucket.this[each.key].arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.this]
}
