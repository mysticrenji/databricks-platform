# Databricks workspace bootstrap

Creates a minimal, least-privilege set of **workspace-local** groups and
automation service principals. It is a workspace-level module and must be
applied in a separate Terraform state after the workspace exists.

The module has no default identities. Define only the groups and principals
required for the environment. Workspace access is enabled by default for an
identity that is created, while SQL, cluster creation, and instance-pool
creation remain disabled by default.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "workspace_bootstrap" {
  source = "./modules/databricks/workspace-bootstrap"

  providers = {
    databricks.workspace = databricks.workspace
  }

  groups = {
    "data-analysts" = {
      databricks_sql_access = true
    }
    "data-engineers" = {
      allow_cluster_create = true
    }
  }

  service_principals = {
    "ci-deployments" = {
      allow_cluster_create = true
    }
  }
}
```

Use OAuth machine-to-machine credentials or workload identity federation for
the workspace provider; do not configure a personal access token in Terraform
source. The credentials used by the provider need workspace administrator
rights to create these objects.

For production identity management, create users, groups, and service
principals at the Databricks account level and use identity federation plus
workspace assignments. This module intentionally creates only workspace-local
identities for small environments or initial bootstrap. Do not use the same
display name for a local identity and a federated account identity.

Membership, administrator assignment, Unity Catalog grants, compute policies,
and instance-profile registration are separate concerns and should be managed
by their respective modules.

## Outputs

- `group_ids`
- `service_principal_ids`
- `service_principal_application_ids`

## References

- [Databricks groups resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group)
- [Databricks service principals resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/service_principal)
