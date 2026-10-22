# Databricks cluster policies

Creates governed Databricks cluster policies and manages explicit permissions
to use or manage them. It uses the workspace-level provider alias,
`databricks.workspace`.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "cluster_policies" {
  source = "./modules/databricks/cluster-policies"

  providers = {
    databricks.workspace = databricks.workspace
  }

  cluster_policies = {
    "shared-engineering" = {
      description = "Bounded shared compute for engineering."
      definition = {
        "spark_version" = {
          type  = "fixed"
          value = "auto:latest-lts"
        }
        "node_type_id" = {
          type          = "allowlist"
          values        = ["m5d.large", "m5d.xlarge"]
          defaultValue  = "m5d.large"
        }
        "num_workers" = {
          type         = "range"
          minValue     = 1
          maxValue     = 8
          defaultValue = 2
        }
        "autotermination_minutes" = {
          type  = "fixed"
          value = 60
        }
      }
      max_clusters_per_user = 2
      permissions = {
        groups = {
          "data-engineers" = "CAN_USE"
        }
      }
    }
  }
}
```

Each policy must define exactly one of:

- `definition`: an HCL object that the module serializes to cluster-policy JSON.
- `policy_family_id`: a Databricks policy family; optional overrides are also
  serialized to JSON.

The permissions map is authoritative for a policy when it has at least one
principal. Manage permissions for the same policy only in this module. Omit
`permissions` to create a policy without delegating non-admin use.

Cluster policies limit configuration but do not grant data access. Use Unity
Catalog grants and external-location permissions to govern data separately.

## Outputs

- `cluster_policy_ids`

## References

- [Databricks cluster policy resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/cluster_policy)
- [Databricks permissions resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/permissions)
## Enforcing Unity Catalog log delivery

The optional `cluster_log_volume_path` defaults to null. Set it to an existing
`/Volumes/catalog/schema/volume` path to enforce fixed, hidden
`cluster_log_conf.type = VOLUMES` and `cluster_log_conf.path` rules on every
configured policy. Both direct definitions and policy-family overrides are
supported. These rules take precedence over existing type/path rules; remove
other legacy cluster_log_conf fields before enabling.

Create the volume and usage/read/write grants in 03-data-access first. This
module creates neither the destination nor permissions. The calling workspace
root reads upstream state; this reusable module accepts paths as inputs.
The compute owner/assigned user needs parent usage
and READ VOLUME/WRITE VOLUME. Supported access modes are Standard and Dedicated
assigned to a user; Dedicated assigned to a group is unsupported for volume log
delivery. Updating a policy does not retrofit running clusters: edit/restart
existing compute with the logging configuration or create new compute under the
policy, and verify actual delivery.

See [compute configuration](https://docs.databricks.com/aws/en/compute/configure)
and [policy reference](https://docs.databricks.com/aws/en/admin/clusters/policy-definition).
## Optional cluster-scoped init script

Set `init_script_volume_path` to an existing UC `.sh` file to fix
`init_scripts.0.volumes.destination` in every configured policy. Default null
adds no rule. Direct definitions and policy families are supported. Index zero
is reserved for this script; conflicting index-zero source settings are rejected.
Existing later init-script indices are not changed.

Set enable_hello_world_init_script=true to upload this module's bundled
scripts/hello-world.sh to init_script_volume_path. The policy depends on the
upload, so both happen in 04-workspace. Upload defaults false: provide only the
path to reference an existing script owned elsewhere. With upload enabled this
module owns the destination file.

03-data-access creates the destination volume and read permissions first.
The retired deployment needs no file import. Other live deployments with an
earlier upload owner require an explicit state migration; never manage the same
file in two states.
The output hello_world_init_script_path belongs to this module / 04-workspace.
Use Dedicated assigned-user compute (the current dev policy) with READ VOLUME
and parent usage permissions. Standard compute additionally requires an admin
allowlist entry for the script. Serverless does not support init scripts.
Changes require restarting/updating existing compute or creating new compute.
A nonzero script exit can fail cluster startup, so the demo only prints metadata.
See [cluster-scoped scripts](https://docs.databricks.com/aws/en/init-scripts/cluster-scoped).
