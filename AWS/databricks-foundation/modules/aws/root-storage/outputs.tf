output "bucket_name" {
  description = "Name of the Databricks root storage bucket."
  value       = aws_s3_bucket.root.bucket
}

output "bucket_arn" {
  description = "ARN of the Databricks root storage bucket."
  value       = aws_s3_bucket.root.arn
}

output "s3_uri" {
  description = "S3 URI of the Databricks root storage bucket."
  value       = "s3://${aws_s3_bucket.root.bucket}"
}
