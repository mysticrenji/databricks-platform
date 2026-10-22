# Deprovision an environment/workspace

Dev/demo now retires root04 persona compute before workspace features, account
groups and infra. Preview-only runs preview compute and features, then stop before
account/infra. Unknown legacy root04 ownership requires reviewed retirement/migration;
it is not silently destroyed. Direct feature retirement rejects managed root04.
The existing destroy opt-in/confirmation and storage retention/purge safeguards
remain in force. See the [compute guide](../databricks-access/COMPUTE.md).

## Workspace features before dataset access

Dev/demo provisioning runs `01-infra → 02-account → 02-workspace-access → 04-workspace compute`.
Root 02 retains groups and USER/ADMIN assignments; the new workspace-only root
owns the feature matrix from `platform/access/roles.yaml` through
`modules/databricks/workspace-entitlements`. State:
`databricks/dev/demo/02-workspace-access.tfstate`. No dataset/metastore registration,
users, membership or compute creation is required. Root 05 excludes these entitlements.

Admins have workspace/SQL and admin compute capabilities; engineers/ML have
workspace/SQL with unrestricted cluster/pool creation disabled; analysts have SQL
only with both compute capabilities disabled. Other groups/inheritance can widen
access. Dataset and compute ACLs remain separate.

Live feature planning and apply run on main only. CI runs this step after account
provisioning; a fresh workspace requires reviewed
root 02 apply before feature planning. Apply is main-only, uses the same-run saved
plan, provisioning opt-in and the dev/demo single-admin policy. Deprovision uses
the separate destroy opt-in and the same admin/manual/main checks, and retires features
before account groups; a dev/demo dry run previews compute and feature retirement.
Other targets are unchanged. No implicit adoption, state migration or live apply
is performed during development. See the [feature runner guide](../databricks-access/README.md).


Use **Actions → Deprovision environment YAML → Run workflow**. Select both
`target_environment` (dev or staging) and `target_workspace` (such as sandbox).
The runner calls `terraform destroy` internally, in reverse order:
root 02 then root 01. This version refuses deployments with live managed
resources in roots 03/04; those roots need their existing reviewed teardown first.

## Single-admin dev/demo deprovisioning

For the private demo repository, required environment reviewers are not needed.
After merging these changes to main, retain the matching backend/account settings
and credentials in `dev-demo-plan` and `dev-demo-apply`, and set
`ENVIRONMENT_YAML_DESTROY_ENABLED=true` in `dev-demo-apply`.

As a repository administrator, start a fresh **Deprovision environment YAML** run:

- Branch: `main`
- `target_environment`: `dev`
- `target_workspace`: `demo`
- `execute_destroy`: `true`
- `confirm_environment`: `dev/demo`
- `purge_storage`: `false` to retain workspace storage (the default)

For permanent workspace storage deletion, select `purge_storage=true` and also
enter `confirm_purge_storage=dev/demo`. This is separate from teardown confirmation.
The backend state bucket/history and KMS resources are always preserved.

Feature retirement and account/infra destruction verify manual workflow_dispatch
on main, exact target confirmation, destroy opt-in and administrator permission
for both the initiating and rerunning actors. Provisioning's apply opt-in cannot
authorize destruction. Preview-only runs require no destroy opt-in; dev/demo
previews compute and feature retirement. All preview/state/ownership bindings and the
fresh six-root empty-state check before purge remain in force. Run tests with
mocked services only; no live teardown or purge is performed during development.

The exception is limited to dev/demo. Other targets and root05 dataset permission
apply retain their existing approval policies.

## Storage retention and optional permanent cleanup

Retention is the default. To remove workspace storage as part of decommissioning,
select `purge_storage=true` along with `execute_destroy=true` and type the exact
`environment/workspace` in **both** `confirm_environment` and
`confirm_purge_storage` (for example `dev/demo`). The target's execution policy
(single-admin checks for dev/demo, protected approvals elsewhere) and
`ENVIRONMENT_YAML_DESTROY_ENABLED=true` still apply. This option
permanently deletes data; it is not a soft delete or a lifecycle expiration rule.

The sequence is feature retirement (dev/demo), `02-account`, `01-infra`, then
storage purge. Infra preview produces `purge-storage.json` before releasing any
ownership. It lists only buckets recorded in the selected infra state whose
addresses and names match rendered workspace inputs: workspace root, landing,
UC-managed, and the optional observability bucket. It reports object-version,
delete-marker and multipart-upload counts and stored bytes. Account ownership,
region, source, inputs, states and content digests are checked before execution.
Preview performs read-only S3 calls and local Terraform state changes only.
An incomplete state-owned bucket inventory blocks purge rather than silently
leaving configured buckets behind; use the earlier backup for reviewed recovery.

After Terraform successfully destroys infra, the runner verifies all six states
(infra, account, data access, workspace, permissions and feature entitlements) are
empty or absent. It then deletes every object version and delete marker, aborts
incomplete multipart uploads, deletes each inventoried bucket, and verifies that
each returns Not Found. A failed deletion or remaining bucket fails the workflow.
It never bypasses Object Lock, legal holds or MFA Delete. KMS keys/aliases and the
Terraform state bucket/history remain retained, including when purge is selected.

The deployment role needs `s3:ListBucket`, `s3:GetBucketLocation`,
`s3:ListBucketVersions`, `s3:ListBucketMultipartUploads`, `s3:DeleteObject`,
`s3:DeleteObjectVersion`, `s3:AbortMultipartUpload` and `s3:DeleteBucket`, scoped
to the selected workspace buckets and objects. Plan credentials need the read
subset. This change does not broaden the deployment IAM role automatically.

For manual runner use, install `tools/environment/requirements-storage.txt` and
add `--purge-storage` to preview and destroy, plus
`--confirm-purge-storage dev/demo` to destroy, alongside the existing arguments.
Deleting a workspace in the Databricks console does not trigger this workflow.

### Retention when purge is not selected

All Terraform-managed S3 and KMS resources in each selected root are retained:
workspace/data/log buckets, their configuration, encryption keys, and aliases.
Even empty buckets are retained. AWS storage and key charges can continue.

Before destruction, the runner backs up state and releases Terraform ownership
of retained resources with `terraform state rm`. This does not delete the
resources or their objects. Preview performs that operation only against a local
state copy. The original remote state is not changed during preview.

Retained resources need a new owner. Preserve the original state and address
inventory, then import them into a separate retention stack. Do not provision
again with retained names under fresh state without resolving ownership first.
IAM roles are destroyed, so continued data access needs independent permissions.
The workflow does not export workspace/catalog metadata or delete a shared
regional metastore. The state bucket and its history are not deleted.

## GitHub Environment settings

For dev/sandbox, use **dev-sandbox-plan** and **dev-sandbox-apply**. Configure
the same config path, role/account, bucket/region, and four namespaced state keys
on both. The [setup helper](../github-environment-setup/README.md) fills them:

```text
TF_INFRA_STATE_KEY=databricks/dev/sandbox/01-infra.tfstate
TF_ACCOUNT_STATE_KEY=databricks/dev/sandbox/02-account.tfstate
TF_DATA_ACCESS_STATE_KEY=databricks/dev/sandbox/03-data-access.tfstate
TF_WORKSPACE_STATE_KEY=databricks/dev/sandbox/04-workspace.tfstate
```

Keys outside the selected environment/workspace namespace are rejected. All four
states must use the configured bucket/region. Root 03/04 missing objects or
states with no managed resources pass; permissions errors fail the check.
The role needs read access to all four states, bucket listing, locking, and
normal resource-deletion permissions. Old deployments with other state layouts
need separately reviewed migration or teardown; do not point at unused keys
to hide resources.

Configure required reviewers and branch restrictions on the apply environment
for targets other than dev/demo; dev/demo uses the single-admin policy above.
Update AWS OIDC trust for the new plan/apply environment names, preserving any
immutable owner/repository IDs in the subject prefix. Add this variable only to
the apply environment:

```text
ENVIRONMENT_YAML_DESTROY_ENABLED=true
```

Provisioning's apply opt-in does not authorize destruction. From the foundation
directory, this helper command configures the separate destroy opt-in:

```bash
python3 tools/github-environment-setup/setup_github_environments.py dev \
  --workspace demo \
  --repo mysticrenji/databricks-platform-engineering \
  --config platform/environments/dev/demo.yaml \
  --state-bucket databricks-platform-nl \
  --state-region eu-central-1 \
  --databricks-client-id YOUR_DATABRICKS_CLIENT_ID \
  --enable-destroy \
  --execute
```

This example configures dev/demo. All four keys are derived from
the selected identity. Each omitted enable flag is set to false on repeat setup;
also pass `--enable-apply` to keep provisioning enabled.

## Preview and execute

1. Commit the version-2 YAML and review its environment/workspace settings.
2. Dispatch the workflow with `execute_destroy` unchecked. Dev/demo previews
   feature retirement only. Other targets preview root 02; root 01 is previewed
   after root 02 is empty. Preview uses local state
   and runs `terraform plan -destroy` without modifying remote state/resources.
3. Inspect logs and download the `destroy-02-account` artifact. Backups contain
   sensitive state. Artifacts expire after one day; preserve backups and
   inventories in approved durable storage before execution. Enable state-bucket
   versioning for recovery.
4. Start a new run with `execute_destroy` checked. Set `confirm_environment`
   to the exact combined identity, for example **dev/sandbox** or **dev/demo**.
   Review its new account preview. Dev/demo verifies administrator permission;
   other targets retain their environment approval before root-02 execution.
5. After account destruction succeeds, review the root-01 preview, preserve
   `destroy-01-infra` backups/inventory. Infrastructure execution uses the same
   target-specific administrator or reviewer policy.

Provision and destroy share a concurrency group for the selected pair; unrelated
workspaces can run independently. Coordinate external Terraform operators.
Execution checks source, config, backend, artifact hashes, and state snapshots.
After releasing retained storage ownership, it regenerates a destroy plan and
compares resource changes with the preview before calling
`terraform destroy -input=false -auto-approve`. Mutations use state locking.
Direct destroy replans internally, so separate preview/execution calls are not
atomic against operators outside this workflow.

## Failure and recovery

Failures stop the sequence. A failed account destroy blocks infra teardown.
Retained storage may already be detached when a later step fails; it remains
in AWS. Preserve the earlier artifact and review a fresh preview before retrying.
Partial deletion leaves the remaining resources in state. An absent/empty
selected state is a no-op in retention-only mode; verify its key before accepting
that result. Purge mode rejects missing bucket ownership inventory.

Do not restore an old full state over partially destroyed infrastructure or
delete state to clear an error. Use backed-up resource IDs to import retained
resources into their new owner stack.

If an opted-in purge fails after Terraform teardown, preserve the infra preview's
`purge-storage.json` and `01-infra.before.tfstate` before the artifact expires.
The buckets have already been detached, so a fresh run must not guess bucket
names from YAML or silently report them cleaned. Review the saved inventory,
verify current ownership and empty deployment states, and complete the remaining
bucket deletion as an explicit recovery operation. Do not restore the full old
state over the destroyed infrastructure.

This implementation does not migrate or delete old
environment-only state namespaces or settings.
