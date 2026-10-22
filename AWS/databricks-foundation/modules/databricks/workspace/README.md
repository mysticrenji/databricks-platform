# Databricks workspace

Creates one Databricks workspace from account-level credential, root-storage,
and network configuration IDs. Create and apply the `account-configuration`
module first.

The module uses the account-level Databricks provider alias,
`databricks.accounts`. Configure the provider in the environment root, never in
this reusable module.

```hcl
provider "databricks" {
  alias      = "accounts"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}

module "workspace" {
  source = "./modules/databricks/workspace"

  providers = {
    databricks.accounts = databricks.accounts
  }

  databricks_account_id       = var.databricks_account_id
  workspace_name              = "analytics-dev"
  aws_region                  = "eu-central-1"
  credentials_id              = module.account_configuration.credentials_id
  storage_configuration_id    = module.account_configuration.storage_configuration_id
  network_id                  = module.account_configuration.network_id
  pricing_tier                = "PREMIUM"
}
```

The input references create Terraform dependencies when both modules are
called from the same root. If account configuration is consumed through remote
state, apply that state before this module.

This module does not configure workspace-level resources, create personal
access tokens, or configure PrivateLink. Use `workspace_url` and a separately
configured workspace-level Databricks provider in a later state for catalogs,
identities, compute policies, and other workspace configuration.

Set `pricing_tier = "ENTERPRISE"` before adding Enterprise-only features such
as PrivateLink. A private connectivity implementation requires separate
Databricks PrivateLink endpoint registrations and private access settings; the
AWS S3, STS, and Kinesis endpoints are not those registrations.

## Outputs

- `workspace_id`
- `workspace_url`

## References

- [Databricks AWS workspace provisioning guide](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/aws-workspace)
- [Databricks workspace resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_workspaces)
