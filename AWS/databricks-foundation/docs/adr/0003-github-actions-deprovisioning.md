# ADR 0003: Deprovision environments through GitHub Actions

> Single-admin amendment (2026-10-18): dev/demo deprovisioning does not require
> GitHub environment reviewers. Require manual workflow_dispatch on main,
> execute_destroy=true, ENVIRONMENT_YAML_DESTROY_ENABLED=true and exact dev/demo
> confirmation. Verify initiating and rerunning actors have repository admin
> permission before feature retirement and each root destruction. Apply opt-in
> cannot authorize destroy. Retain all preview/backend/state/ownership checks,
> storage retention defaults, separate purge confirmation, six-root empty-state
> checks, and backend/KMS preservation. Other targets and root05 permissions keep
> their existing approvals. No live destruction or purge runs during development.

> Storage cleanup amendment (2026-10-18): retention remains the default. Manual
> decommissioning now supports `purge_storage=true` plus separate exact workspace
> confirmation. The infra preview saves a state-derived, configuration-checked
> bucket inventory and content digests. After successful Terraform teardown and
> fresh empty-state checks, Python uses the S3 API to purge object versions,
> delete markers and incomplete uploads, delete those buckets, and verify absence.
> This explicit post-teardown step is the exception to Terraform-only deletion
> below; it never deletes KMS resources or backend storage/history. Errors fail
> the workflow. Preserve the preview inventory for reviewed partial-failure
> recovery. See the [operational guide](../../tools/environment/DEPROVISIONING.md).

> Future integration: [ADR 0005](0005-api-driven-access-and-compute.md) requires
> API-inventory checks and retirement of API-managed workspace resources before
> enabling the new access layer. The current workflow checks Terraform states;
> empty downstream states will not prove absence of future API-managed resources.
> This requirement is not implemented by the ADR documentation change.

> [ADR 0004](0004-environment-workspace-isolation.md) extends this workflow with
> workspace selection. GitHub Environments are now `<environment>-<workspace>-apply`
> and `-plan`, all four keys use `databricks/<environment>/<workspace>/`, and
> confirmation is `<environment>/<workspace>`. The retention strategy below is
> unchanged. Use the current operational guide for commands.

- Date: 2026-10-16
- Status: Implemented on feature branch; live adoption pending
- Scope: Manual deprovisioning of Terraform-managed Databricks workspaces and AWS infrastructure
- Related: [ADR 0002: Environment YAML provisioning](0002-environment-yaml-provisioning.md)

## Context

The provisioning GitHub Actions workflow and Python runner provision dev and
staging using roots `01-infra` and `02-account`. They support plan and apply.
Deleting a YAML file does not remove the workspace or its AWS resources.
Operators need a documented way to deprovision using the same configuration,
credentials, backend bucket, and state keys used for provisioning.

## Decision

Add a separate, manually dispatched GitHub Actions deprovisioning workflow.
Python validates the selected YAML and orchestrates Terraform; Terraform owns
all resource deletion. The execution job must call `terraform destroy`
internally, rather than deleting resources directly through AWS or Databricks
APIs.

Initially support `dev` and `staging` only. Production remains unavailable.
Do not trigger destruction on pull requests, pushes, or YAML deletion.

### Select and validate the deployment

- Select an allowlisted target: `dev` or `staging`.
- Read `ENVIRONMENT_CONFIG_PATH`, with the same default as provisioning. Keep
  the YAML available until deprovisioning is complete.
- Require the YAML environment name, trusted AWS role/account, and Databricks
  account to match the selected target.
- Use the existing `TF_STATE_BUCKET`, `TF_STATE_REGION`,
  `TF_INFRA_STATE_KEY`, and `TF_ACCOUNT_STATE_KEY`. Do not derive replacement
  keys, migrate state, or silently use a new backend.
- Render inputs through the existing adapter and include the selected
  environment's supplemental inputs. Preserve provisioning's isolation from
  local tfvars and Terraform environment overrides.

### Execute roots in reverse dependency order

The initial workflow destroys these roots sequentially:

```text
02-account → 01-infra
```

Destroy the workspace and account registrations while infrastructure outputs
are still available, then destroy the AWS infrastructure. Stop on any failure;
never destroy a prerequisite after a dependent root fails.

When roots 03 and 04 are deployed, they must be destroyed first:

```text
04-workspace → 03-data-access → 02-account → 01-infra
```

The initial two-root workflow must refuse deployments with live resources in
03 or 04 until those roots are supported. The deprovisioning runner requires
explicit `TF_DATA_ACCESS_STATE_KEY` and `TF_WORKSPACE_STATE_KEY` bindings and
reads all four states directly from the configured S3 bucket/region. Missing
objects and states with no managed resources pass the downstream check; access
errors fail it. A workspace name or the absence of a local state file is not
evidence that downstream roots are empty. Other bucket/region layouts are outside
the initial implementation.

### Preview, approval, and Terraform invocation

Default to preview only. Require an explicit execution input and an exact
environment-name confirmation before deletion. Use the matching protected
`<environment>-apply` GitHub Environment with required reviewers and a separate
`ENVIRONMENT_YAML_DESTROY_ENABLED=true` variable. The provisioning variable
`ENVIRONMENT_YAML_APPLY_ENABLED` does not authorize destruction.

For each root, preview against a local copy of its current state. Remove retained
S3 and KMS resource addresses only from that local copy, then show a destroy plan:

```bash
terraform init -input=false -lockfile=readonly
terraform state rm -lock-timeout=60s RETAINED_RESOURCE_ADDRESSES
terraform plan -destroy -input=false -var-file=inputs.json
```

Omit the state-rm command if there are no retained addresses. Upload the
pre-retention state backups, resource inventory, plan changes, and manifest
before execution. Default preview mode previews root 02 only; root 01 is
previewed after root 02 has been destroyed or confirmed empty.

After approval, initialize the original S3 backend, verify the same configuration
and state snapshots, release ownership of retained resources in remote state,
and compare a fresh destroy plan's managed-resource changes with the preview.
Only then run:

```bash
terraform destroy -input=false -auto-approve -var-file=inputs.json
```

`-auto-approve` is used only inside the protected execution job because CI
cannot answer an interactive prompt. It does not replace the approval gate.
Keep Terraform state locking enabled; do not use `-target` or delete state files.
The narrowly scoped state-rm operations release storage ownership only; they do
not delete retained resources, wipe a complete state, or change backend keys.
Share a concurrency group with provisioning for the selected environment, so
provision and destroy cannot run against the same states simultaneously.

Each root's preview must run after its dependent roots have been destroyed,
followed by approval for that root's execution. Direct `terraform destroy`
calculates a new plan; it does not execute the exact earlier preview. Bind
preview and execution to the same commit, YAML, inputs, and backend, and reject
state changes since preview. This reduces drift risk but does not make separate
preview and destroy calls atomic against external operators. If exact saved-plan
execution is required later, amend this decision to use `terraform plan -destroy
-out=destroy.tfplan` followed by `terraform apply destroy.tfplan`.

### Data and failure handling

Retain all S3 and KMS resources in each selected root by default, including
bucket configuration, workspace/data/log buckets, encryption keys, and aliases.
This prevents even empty buckets from being deleted and avoids deleting keys
needed to read retained encrypted data. Identify retained addresses in the
preview and preserve their original state attributes in the backup artifact.
This is a deliberate ownership transfer: retained resources must later be
imported into a separate retention stack. Do not enable `force_destroy`, bypass
deletion protection, or delete a shared regional metastore.

Other resource deletion protections may still block destruction. Report the
blocking resource, retain remaining remote state, and allow a reviewed retry
after the operator resolves it. Do not proceed to the next root on partial
failure. If a failure occurs after storage ownership is released, those resources
remain detached and retained in AWS; use the earlier backup for later import.
Retain the state bucket and state history outside the deployment's lifecycle.
Backups are sensitive; operators must preserve them in approved durable storage
before execution, as workflow artifacts expire after one day. Enable state-bucket
versioning for recovery. IAM access to retained data needs an independent owner
after workspace roles are destroyed. Workspace and catalog metadata exports are
outside this workflow.

## Acceptance criteria

- Production and mismatched YAML/target combinations are rejected before deletion.
- Preview mode performs no resource deletion.
- Execution requires explicit confirmation, protected-environment approval,
  and the destroy-specific opt-in.
- Tests prove reverse order, matching state/input bindings, locking, downstream
  state checks, drift rejection, and stopping after a failed destroy.
- Re-running after partial destruction uses the retained state; it does not
  recreate resources or reset the backend.
- Operational documentation explains retention, first use, approvals, and recovery.

## Consequences

Operators get one explicit CI entry point for deprovisioning and an audit trail
for destructive actions. The implementation is in
`.github/workflows/environment-deprovision.yml`, its reusable
`environment-destroy-root.yml`, and `tools/environment/deprovision_environment.py`.
See [the operational guide](../../tools/environment/DEPROVISIONING.md). Local
tests use mocked AWS/Terraform operations. No live destroy, state mutation, or
GitHub configuration change was performed during implementation.
