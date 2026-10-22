# Optional Databricks root-storage KMS key

Creates a customer-managed KMS key for the Databricks root S3 bucket only when
`enabled = true`. It is disabled by default, so its outputs are null and it
creates no AWS resources.

When enabled, the module enables annual key rotation, uses a 30-day deletion
window, creates a stable alias, permits S3-mediated use from the owning AWS
account, and attaches narrowly scoped KMS usage policies to the Databricks
cross-account and workspace instance-profile roles.

```hcl
module "kms" {
  source = "./modules/aws/kms"

  enabled         = true
  name            = "databricks-prod-eu-central-1"
  aws_region      = "eu-central-1"
  aws_account_id  = "123456789012"

  cross_account_role_name              = module.iam_roles.cross_account_role_name
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
}

module "root_storage" {
  source = "./modules/aws/root-storage"

  # Other root-storage inputs omitted.
  aws_region  = "eu-central-1"
  kms_key_arn = module.kms.key_arn
}
```

The module encrypts S3 workspace root storage. It does not register a
Databricks account-level customer-managed key configuration for managed
services, EBS, or control-plane data; that configuration is a later
Databricks-provider component and has additional regional eligibility
requirements.

Set `aws_account_id`, `cross_account_role_name`, and
`workspace_instance_profile_role_name` only when enabling the key. Cross-account
KMS usage requires both a key policy and IAM permissions; the module configures
the customer-account side for the two workspace roles.

## Outputs

- `enabled`
- `key_arn`
- `key_id`
- `alias_name`

## References

- [Databricks S3 encryption with KMS](https://docs.databricks.com/aws/en/security/keys/kms-s3)
- [AWS KMS cross-account access](https://docs.aws.amazon.com/kms/latest/developerguide/key-policy-modifying-external-accounts.html)
