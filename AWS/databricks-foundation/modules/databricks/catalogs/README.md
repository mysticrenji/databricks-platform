# Unity Catalog catalogs

Creates Unity Catalog catalogs, optional schemas and volumes, and explicit
grants at each level. It uses the workspace-level provider alias,
`databricks.workspace`, after Unity Catalog has been assigned to the
workspace.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "catalogs" {
  source = "./modules/databricks/catalogs"

  providers = {
    databricks.workspace = databricks.workspace
  }

  catalogs = {
    analytics = {
      owner        = "data-engineers"
      storage_root = "s3://company-data-dev/managed/analytics"
      grants = {
        "data-engineers" = ["USE_CATALOG", "CREATE_SCHEMA"]
        "data-analysts"  = ["USE_CATALOG"]
      }
      schemas = {
        curated = {
          grants = {
            "data-engineers" = ["USE_SCHEMA", "CREATE_TABLE"]
            "data-analysts"  = ["USE_SCHEMA"]
          }
          volumes = {
            reference = {
              grants = {
                "data-engineers" = ["READ_VOLUME", "WRITE_VOLUME"]
              }
            }
          }
        }
      }
    }
  }
}
```

Set a catalog or schema `storage_root` only when the S3 path is governed by an
external location and its storage credential. Leaving roots unset uses the
metastore managed-storage location, if configured. `MANAGED` volumes have no
storage location; `EXTERNAL` volumes require an S3 `storage_location` covered
by an external location.

The `grants` map is authoritative for each catalog, schema, or volume where it
is non-empty. Do not manage grants for the same securable in another
`databricks_grants` resource. Omit `grants` when the module must not manage
access for that object.

The module does not use `force_destroy`; remove tables, volumes, and other
children deliberately before destroying a catalog or schema.

## Outputs

- `catalog_ids`
- `schema_ids`
- `volume_ids`
- `volume_paths`

## References

- [Databricks catalog resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/catalog)
- [Databricks schema resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/schema)
- [Databricks volume resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/volume)
- [Databricks grants resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants)
