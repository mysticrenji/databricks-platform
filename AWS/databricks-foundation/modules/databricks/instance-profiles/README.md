# Databricks instance profiles

Registers AWS IAM instance profiles with a Databricks workspace and optionally
grants selected workspace groups permission to use each registered profile.
It must run in a workspace-level Terraform state after both the workspace and
its groups exist.

```hcl
provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.workspace.outputs.workspace_url
}

module "instance_profiles" {
  source = "./modules/databricks/instance-profiles"

  providers = {
    databricks.workspace = databricks.workspace
  }

  instance_profiles = {
    data_access = {
      instance_profile_arn = data.terraform_remote_state.infra.outputs.databricks_instance_profile_arn
      iam_role_arn         = data.terraform_remote_state.infra.outputs.databricks_instance_profile_role_arn
      group_ids = [
        data.terraform_remote_state.workspace_bootstrap.outputs.group_ids["data-engineers"],
      ]
    }
  }
}
```

The profile is registered even when `group_ids` is omitted. No non-admin user
or group receives permission to use it until it is explicitly listed in
`group_ids`. Group access is managed with the current `databricks_group_role`
resource.

`skip_validation` is `false` by default, so Databricks validates whether the
instance profile can launch EC2 instances. Set it to `true` only as a temporary
workaround for a documented AWS propagation or validation issue, then restore
validation.

For new S3 data access, prefer Unity Catalog storage credentials and external
locations. Instance profiles are intended for compute-level AWS access and
legacy workloads that require them.

## Outputs

- `instance_profile_ids`
- `instance_profile_arns`

## References

- [Databricks instance profile resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/instance_profile)
- [Databricks group role resource](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_role)

Use `group_ids_by_name = { engineers = module.bootstrap.group_ids["engineers"] }`
when groups are created in the same apply. The map names remain known during
planning even when group IDs are computed. `group_ids` is retained for existing
IDs; do not assign the same group through both fields.
