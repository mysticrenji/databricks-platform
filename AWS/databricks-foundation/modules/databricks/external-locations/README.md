# Unity Catalog external locations

Creates Unity Catalog external locations for existing S3 paths and storage
credentials. It runs with the workspace-level provider alias,
`databricks.workspace`, after the workspace has a Unity Catalog metastore
assignment.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "external_locations" {
  source = "./modules/databricks/external-locations"

  providers = {
    databricks.workspace = databricks.workspace
  }

  external_locations = {
    raw_data = {
      url             = "s3://company-data-dev/raw"
      credential_name = "company-data-dev"
      read_only       = true
      grants = {
        "data-engineers" = ["READ_FILES", "CREATE_EXTERNAL_TABLE"]
        "data-analysts"  = ["READ_FILES"]
      }
    }
  }
}
```

`credential_name` must name an existing Unity Catalog storage credential whose
AWS IAM role has access to the configured S3 path. The module does not create
AWS buckets, IAM roles, or storage credentials.

`databricks_grants` is authoritative for each external location that has a
non-empty `grants` map. Manage grants for the same location only here; defining
them in another `databricks_grants` resource can overwrite access. Omit
`grants` to register a location without delegating access to non-owners.

Validation is enabled by default. Set `skip_validation = true` only for a
temporary, documented AWS propagation issue and restore validation afterward.
`enable_file_events` remains disabled by default because it requires additional
AWS S3 event-notification permissions and design.

## Outputs

- `external_location_ids`
- `external_location_urls`

## References

- [Databricks external location resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/external_location)
- [Databricks grants resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/grants)
- [Databricks external location guidance](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-external-locations)
