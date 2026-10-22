# Databricks account configuration

Registers AWS resources with a Databricks account. It creates a credential
configuration, root-storage configuration, and customer-managed network
configuration. It does not create a Databricks workspace; the workspace module
consumes the three IDs exported here.

The module uses the account-level Databricks provider alias,
`databricks.accounts`. Configure that provider in an environment root, not in
this reusable module.

```hcl
provider "databricks" {
  alias      = "accounts"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}

module "account_configuration" {
  source = "./modules/databricks/account-configuration"

  providers = {
    databricks.accounts = databricks.accounts
  }

  name                        = "databricks-dev-eu-central-1"
  databricks_account_id       = var.databricks_account_id
  cross_account_role_arn      = data.terraform_remote_state.infra.outputs.databricks_cross_account_role_arn
  root_storage_bucket_name    = data.terraform_remote_state.infra.outputs.root_storage_bucket_name
  vpc_id                      = data.terraform_remote_state.infra.outputs.vpc_id
  workspace_subnet_ids        = data.terraform_remote_state.infra.outputs.workspace_subnet_ids
  workspace_security_group_id = data.terraform_remote_state.infra.outputs.workspace_security_group_id
}
```

Authenticate the account-level provider with OAuth machine-to-machine
credentials, workload identity federation, or another approved account-admin
authentication method. Do not place a long-lived token in Terraform source or
state inputs.

The AWS service endpoints created in `infra` are not Databricks PrivateLink
endpoints and are not registered here. Add Databricks PrivateLink endpoint
registrations only when you create the distinct REST API and secure-cluster
connectivity endpoints.

Network configuration updates are replacement operations. Once a network is
attached to a running workspace, create a replacement configuration, update the
workspace to it, and only then remove the old configuration.

## Outputs

- `credentials_id`
- `storage_configuration_id`
- `network_id`

## References

- [Databricks AWS workspace provisioning guide](https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/aws-workspace)
- [Databricks network configuration resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_networks)
