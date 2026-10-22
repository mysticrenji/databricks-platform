# Databricks SQL warehouses

Creates Databricks SQL warehouses with bounded capacity, automatic shutdown,
optional serverless compute, tags, and explicit access permissions. It uses the
workspace-level provider alias, `databricks.workspace`.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "sql_warehouses" {
  source = "./modules/databricks/sql-warehouses"

  providers = {
    databricks.workspace = databricks.workspace
  }

  warehouses = {
    "analytics-bi" = {
      cluster_size              = "Small"
      auto_stop_mins            = 10
      min_num_clusters          = 1
      max_num_clusters          = 2
      enable_serverless_compute = true
      tags = {
        environment = "dev"
        cost_center = "analytics"
      }
      permissions = {
        groups = {
          "data-analysts"  = "CAN_USE"
          "data-engineers" = "CAN_MANAGE"
        }
      }
    }
  }
}
```

Each warehouse defaults to a Small warehouse, one cluster, Photon enabled, and
a 10-minute auto-stop window. Set `enable_serverless_compute` only when
serverless SQL warehouses are enabled in the Databricks account and region.

The permission maps are authoritative for each warehouse where they are
non-empty. Manage a warehouse's permissions only in this module. Omit
`permissions` to create the warehouse without granting non-admin access.

Warehouse permissions govern query-compute access. Use Unity Catalog grants to
govern data access separately.

## Outputs

- `warehouse_ids`
- `jdbc_urls`

## References

- [Databricks SQL warehouse resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/sql_endpoint)
- [Databricks permissions resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/permissions)
