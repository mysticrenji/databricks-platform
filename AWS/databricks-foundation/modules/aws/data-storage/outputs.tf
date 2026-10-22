output "buckets" {
  description = "Bucket names, ARNs, and S3 URLs keyed by landing, uc_managed, and optional observability."
  value = {
    for key, bucket in aws_s3_bucket.this : key => {
      name = bucket.bucket
      arn  = bucket.arn
      url  = "s3://${bucket.bucket}"
    }
  }
}
