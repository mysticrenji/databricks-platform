# Databricks root S3 storage

Creates the root S3 bucket required by a Databricks workspace for workspace
assets, libraries, logs, and the default catalog. It also grants the workspace
EC2 instance-profile role only the S3 permissions it needs for this bucket.

The bucket enables S3 Block Public Access, bucket-owner-enforced ownership,
versioning, default SSE-S3 encryption, and a deny for non-TLS requests. The
bucket policy grants the Databricks control plane access only when its principal
has the supplied Databricks account ID tag, and prevents DBFS access to the
`unity-catalog/` prefix.

```hcl
module "root_storage" {
  source = "./modules/aws/root-storage"

  name                                 = "databricks-dev-eu-central-1"
  bucket_name                          = "my-company-databricks-dev-euc1-root"
  databricks_account_id                = var.databricks_account_id
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
}
```

Bucket names are global. Include an organization-controlled unique suffix; do
not use the example bucket name unchanged. The module deliberately sets
`force_destroy = false`, so Terraform will not destroy a non-empty root bucket.

This module uses S3-managed encryption (`AES256`) when `kms_key_arn` is null.
Pass the ARN from the optional [KMS module](../kms/README.md) and the AWS region
to switch the bucket to SSE-KMS.

Do not add restrictive VPC endpoint policies or source-VPC bucket conditions
until the Databricks required regional buckets, control-plane access, and any
cross-region storage use are designed together.

## Outputs

- `bucket_name`
- `bucket_arn`
- `s3_uri`

## References

- [Databricks workspace storage configuration](https://docs.databricks.com/aws/en/admin/workspace/create-uc-workspace)
- [AWS S3 public-access guidance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/granting-public-access.html)
