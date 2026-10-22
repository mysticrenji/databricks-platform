# Development workspace configuration

Run fourth, after 01-infra → 02-account → 03-data-access.
This root reads all three upstream states. It configures explicitly requested
workspace-local identities, instance-profile registration, compute policies,
SQL warehouses, and jobs. Metastore setup and all UC data objects belong to 03.
Prefer account groups created in 02-account for permissions.

Set state_bucket/state_region and the infra_state_key, account_state_key, and
data_access_state_key values to match upstream backend files. Local dev uses
`databricks-foundation/dev/`; examples use `databricks/dev/`. Its backend has a
new key ending in `04-workspace.tfstate`. After updating the checkout, run:

```bash
terraform init -reconfigure -backend-config=backend.hcl
terraform plan
terraform apply
```

Databricks credentials must be authorized in the workspace. If enabling logging
or the hello-world script, the paths in tfvars must match the volumes created in
03-data-access. Keep path inputs null and upload disabled when those volumes are
not configured. The policy creates no running cluster. Warehouses and jobs
remain opt-in; review any configured compute costs before applying.

See the [development guide](../README.md) and
[init-script guide](../../../README.md#hello-world-init-script).
Destroy this root before 03-data-access so files/policies are removed while their
volumes and metastore assignment still exist. For other live deployments with
old nonempty states, plan state migration before using the renamed root.

## Generated dev/demo persona compute

The separate compute renderer/runner deploys `platform/compute/dev.yaml` and the
persona ACLs from `platform/access/roles.yaml` through this existing root. It uses
`databricks/dev/demo/04-workspace.tfstate`; it does not introduce another owner for
policies or SQL warehouses. Engineers receive `CAN_USE` on `engineering-standard`,
ML receives `CAN_USE` on `ml-standard`, and analysts use the `analytics` SQL
warehouse. The warehouse ACL also grants engineers/ML `CAN_USE` and admins
`CAN_MANAGE`. Workspace admins already manage cluster policies.

Generated inputs explicitly set `read_data_access_state=false`, so this deployment
requires roots 01/02 but no metastore, catalogs, or root 03 state. It disables UC
logging paths and init script upload. Legacy callers retain the default `true`
and their existing root 03 ordering. The runtime runner binds `compute_identity`
and `compute_group_ids` to verified root 02 outputs; mismatched workspace IDs,
URLs, group IDs or upstream namespace keys fail before compute resources plan.
The runner performs additional read-only live identity and ownership checks.

Policies define permitted compute and do not start clusters. Creating a SQL
warehouse provisions its configuration and may incur compute charges if used;
it is bounded to one cluster with automatic shutdown. No cluster/job execution
is used for verification. Group membership, assignments, entitlements and UC
grants retain their existing owners.

Offline checks use `terraform test` for the default handoff suite and
`terraform test -test-directory=generated-tests -var-file=/path/to/compute.tfvars.json`
for the rendered persona inputs. Both use mocked providers and state outputs.
