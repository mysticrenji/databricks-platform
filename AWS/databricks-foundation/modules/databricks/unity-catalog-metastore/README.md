# Unity Catalog metastore

Creates a Unity Catalog metastore and assigns it to one Databricks workspace.
This module uses the account-level provider alias, `databricks.accounts`, and
must run after the workspace module.

By default it creates a metastore **without** a metastore-level managed-storage
root. This supports the recommended model of defining separate managed-storage
locations per catalog. If a shared metastore storage root is required, provide
both an existing Unity Catalog storage credential ID and its S3 path.

```hcl
provider "databricks" {
  alias      = "accounts"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}

module "unity_catalog_metastore" {
  source = "./modules/databricks/unity-catalog-metastore"

  providers = {
    databricks.accounts = databricks.accounts
  }

  metastore_name = "company-eu-central-1"
  aws_region     = "eu-central-1"
  workspace_id   = tonumber(data.terraform_remote_state.workspace.outputs.workspace_id)
  owner          = "uc-admins"
}
```

To configure a shared metastore root, create the AWS S3 bucket, IAM role, trust
policy, and Unity Catalog storage credential first. The IAM role trust policy
must use the Unity Catalog IAM principal and external ID returned for that
storage credential. Then pass both values together:

```hcl
storage_root               = "s3://company-uc-eu-central-1/metastore"
storage_root_credential_id = module.storage_credential.storage_credential_id
```

The module deliberately does not create AWS buckets, IAM roles, or storage
credentials. Those require an AWS trust-policy handshake based on the external
ID returned by Databricks, and should be handled by dedicated AWS and storage
credential modules. The next module, `external-locations`, can use a separate
storage credential and bucket for each governed data domain.

## Outputs

- `metastore_id`
- `metastore_assignment_id`
- `metastore_storage_root`

## References

- [Databricks metastore resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore)
- [Databricks metastore assignment resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/metastore_assignment)
- [Databricks guidance for storage credentials](https://docs.databricks.com/aws/en/connect/unity-catalog/cloud-storage/manage-storage-credentials)
