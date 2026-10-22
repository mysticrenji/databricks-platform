# Environment and workspace provisioning

Dev/demo provisioning now includes persona compute after entitlements:
01-infra → 02-account → 02-workspace-access → 04-workspace compute. Policies,
analytics SQL and group ACLs come from the existing platform YAML. The compute
path needs no root03 data state and retains the existing admin/opt-in/confirmation
checks. See the [compute guide](../databricks-access/COMPUTE.md); a future SQL
warehouse apply can start billable compute. Other targets keep their existing path.

For decommissioning, the manual workflow retains storage by default. Optional
`purge_storage=true` and a separate matching `confirm_purge_storage` remove all
versions, delete markers, incomplete uploads and reviewed workspace buckets only
after successful teardown. State storage and KMS remain retained. See the
[deprovisioning guide](DEPROVISIONING.md) for confirmation, IAM and recovery details.

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
plan, provisioning opt-in and protected reviewers. Deprovision retires features
before account groups; a dev/demo dry run previews compute and feature retirement.
Other targets are unchanged. No implicit adoption, state migration or live apply
is performed during development. See the [feature runner guide](../databricks-access/README.md).


One version-2 YAML declares one deployment identified by `environment.name`
and `workspace.name`. Python validates it and renders inputs for roots
`01-infra` then `02-account`. Root 02 also provisions configured account groups
and their workspace assignments. Catalog/schema access and compute remain separate.

Administrator YAML and supplemental JSON now live under `platform/`; Terraform
execution roots stay in top-level `environments/`. See the [platform guide](../../platform/README.md)
for folder responsibilities and updating existing GitHub ENVIRONMENT_CONFIG_PATH
variables in both plan/apply environments after the move. State keys are unchanged.

```text
platform/environments/
  dev/
    shared.yaml
    sandbox.yaml
    demo.yaml                # Demo workspace
  staging/
    shared.yaml
  production/               # Configuration-only; unavailable to CI
    analytics/environment.yaml
    data-engineering/environment.yaml
    ml-platform/environment.yaml
```

Identity fields in each complete document:

```yaml
version: 2
environment:
  name: dev
  aws_account_id: "YOUR_ACCOUNT_ID"
  aws_region: eu-west-1
  deployment_role_arn: arn:aws:iam::YOUR_ACCOUNT_ID:role/YOUR_DEPLOYMENT_ROLE
workspace:
  name: sandbox
```

Complete templates also contain `databricks`, `network`, `storage`, and
`features`. Workspace identifiers are lowercase slugs of at most 16 characters.
The cloud workspace name is derived as `dev-sandbox`. Do not include the old
`databricks.workspace_name` field. AWS names and tags include both identifiers.
The YAML filename is not the deployment identity.

## Separate state and inputs

For dev/sandbox, all four keys use this namespace:

```text
databricks/dev/sandbox/01-infra.tfstate
databricks/dev/sandbox/02-account.tfstate
databricks/dev/sandbox/03-data-access.tfstate
databricks/dev/sandbox/04-workspace.tfstate
```

The same S3 bucket can hold dev/shared, dev/demo, and staging/shared under
different prefixes. The runner rejects keys outside the selected namespace.
Root 02 checks the environment/workspace identity exported by root 01.

Optional platform settings live in
`platform/terraform-inputs/<environment>/<workspace>.01-infra.json` and
`<workspace>.02-account.json`. Create these files, initially `{}`, when adding
a workspace. Inputs are allowlisted and cannot override YAML or backend settings.
Carry forward memberships, budgets, Kinesis, and log settings before adoption;
empty files use Terraform defaults. No live equivalence is implied.

Dev/demo's account supplemental JSON enables the first workspace-access layer:

| Account group | Workspace role |
| --- | --- |
| `dev-demo-admins` | ADMIN |
| `dev-demo-engineers` | USER |
| `dev-demo-analysts` | USER |
| `dev-demo-ml` | USER |

The existing provisioning workflow passes these inputs to root 02; assignments
reference the newly created workspace ID. All member maps are empty, so Terraform
creates no membership resources and does not clear externally managed membership.
Users gain group access after an identity administrator adds them to the account
group. Preserve the deployment identity and independent recovery administrator.
No dataset or compute setup is needed for this layer. No persona entitlements are
configured; workspace defaults/other memberships and ADMIN privileges still apply.
Other workspace supplemental files remain unchanged; nothing is auto-enabled there.

Select `target_environment=dev`, `target_workspace=demo` in provisioning CI.
Deployment uses the single-admin dev/demo policy below and explicit Terraform apply opt-in.
No live plan/apply runs during tests. Matching group names are not an import:
existing groups require separately reviewed ownership/import before apply.
Use root 02's `account_group_ids` output for later verified identity binding.
Regenerate saved plans after changing supplemental inputs; the runner binds these
inputs in its manifest and rejects changes when applying a saved plan.

The runner copies source into an isolated temporary directory, excluding local
tfvars, backend files, plans, and `.terraform`. It rejects Terraform CLI,
variable, workspace, and data-directory environment overrides. Manual Terraform
commands must also use the new identity inputs.

## Validate locally

Use Python 3.10 or later. From `AWS/databricks-foundation`:

```bash
python3 -m venv /tmp/databricks-environment-venv
/tmp/databricks-environment-venv/bin/pip install -r tools/environment/requirements.txt
/tmp/databricks-environment-venv/bin/python -m unittest discover -s tools/environment/tests -v
/tmp/databricks-environment-venv/bin/python tools/environment/environment.py validate platform/environments/dev/sandbox.yaml --example
```

Replace placeholders before rendering or deployment. `--example` is validation
only. With real values:

```bash
python3 tools/environment/environment.py validate platform/environments/dev/sandbox.yaml
python3 tools/environment/environment.py render platform/environments/dev/sandbox.yaml --output /tmp/dev-sandbox-inputs
```

Unknown fields, duplicate keys, aliases, invalid types, overlapping subnets,
and role/account mismatches fail validation. Single-NAT mode requires one NAT
subnet serving all private subnets; per-AZ mode requires same-AZ mappings.
Offline checks do not prove real privileges, global bucket-name availability,
AZ access, or quotas. Review region support before extending `environment.py`.

## GitHub Actions settings

The manual workflow takes `target_environment` (dev or staging) and
`target_workspace` (such as sandbox). Defaults are dev/shared and plan-only.
Provision and destroy share a concurrency group for that exact pair.
Production is unavailable.

Create protected GitHub Environments for each pair:

```text
dev-shared-plan       dev-shared-apply
dev-sandbox-plan      dev-sandbox-apply
dev-demo-plan      dev-demo-apply
staging-shared-plan   staging-shared-apply
```

Set matching variables and secret on each pair:

| GitHub variable | Example for dev/sandbox |
| --- | --- |
| `ENVIRONMENT_CONFIG_PATH` | `AWS/databricks-foundation/platform/environments/dev/sandbox.yaml` |
| `AWS_DEPLOYMENT_ROLE_ARN` | Existing deployment role ARN matching YAML |
| `DATABRICKS_ACCOUNT_ID` | Databricks account UUID matching YAML |
| `DATABRICKS_CLIENT_ID` | OAuth service-principal client ID |
| `TF_STATE_BUCKET` | Existing Terraform state bucket |
| `TF_STATE_REGION` | Actual state bucket region |
| `TF_INFRA_STATE_KEY` | `databricks/dev/sandbox/01-infra.tfstate` |
| `TF_ACCOUNT_STATE_KEY` | `databricks/dev/sandbox/02-account.tfstate` |
| `TF_DATA_ACCESS_STATE_KEY` | `databricks/dev/sandbox/03-data-access.tfstate` |
| `TF_WORKSPACE_STATE_KEY` | `databricks/dev/sandbox/04-workspace.tfstate` |

Store `DATABRICKS_CLIENT_SECRET` as a **secret** in both environments. Configure
required reviewers, prevent self-review where supported, and restrict deployment
branches on apply environments before adding `ENVIRONMENT_YAML_APPLY_ENABLED=true`,
except for the single-admin dev/demo provisioning policy below.
Destroy requires a separate opt-in.

`ENVIRONMENT_CONFIG_PATH` is a committed path relative to the repository root,
not a URL. If unset, CI uses `platform/environments/<environment>/<workspace>.yaml`
under the foundation. Custom files must declare the selected identity.

CI maps the role to `EXPECTED_DEPLOYMENT_ROLE_ARN` and the backend variables to
`STATE_BUCKET`, `STATE_REGION`, `INFRA_STATE_KEY`, and `ACCOUNT_STATE_KEY`.
Do not create these internal names, `CONFIG`, `TARGET_ENVIRONMENT`,
`TARGET_WORKSPACE`, or `TF_IN_AUTOMATION` manually.

Update the role's AWS OIDC trust for the **new** environment subjects, such as
`environment:dev-sandbox-plan` and `environment:dev-sandbox-apply`. Preserve
any immutable owner/repository IDs in the subject prefix. Old dev-plan/dev-apply
trust entries do not cover the new names. The
[setup helper](../github-environment-setup/README.md) fills all four keys.

## Workflow behavior

### Single-admin dev/demo deployment

The private demo repository uses a single-admin provisioning policy, without
GitHub environment reviewer requirements. In `dev-demo-apply`, retain the matching
backend/account/credential settings and set `ENVIRONMENT_YAML_APPLY_ENABLED=true`.
After merging these changes to main, open **Actions → Provision environment YAML →
Run workflow** as a repository administrator and select:

- Branch: `main`
- `target_environment`: `dev`
- `target_workspace`: `demo`
- `deploy`: `true`
- `confirm_environment`: `dev/demo`

The read-only preflight verifies the manual main run, confirmation, opt-in and
administrator permission before creating infrastructure. Both provisioning roots
and feature apply recheck the same policy and consume their same-run saved plans.
Reruns must also be initiated by an administrator. `deploy=false` remains plan-only
and needs no apply confirmation; a fresh workspace still needs root02 apply before
feature planning. Regenerate plans after changing source or inputs.

This exception also covers dev/demo deprovisioning and feature retirement using
the separate destroy opt-in, execute_destroy=true and exact dev/demo confirmation.
Optional storage purge needs its separate confirmation. See the
[deprovisioning guide](DEPROVISIONING.md#single-admin-devdemo-deprovisioning).
Dataset permission apply still requires environment reviewers and its own opt-in;
it remains blocked when reviewer protection is unavailable.
Staging and other workspaces retain their existing deployment requirements.


Pull requests/main pushes run tests, validate all dev/staging YAMLs with
`--example`, check formatting, and initialize/validate roots without backend
access. Production templates are not read by Actions. Jobs use Ubuntu 24.04,
Node 24 actions, and Terraform 1.10.5.

Deployment runs infra plan/apply before account plan/apply. Plan-only account
preview needs existing infra state; a first deployment fails there until infra
has been applied. Plans are not combined across roots.

Provisioning apply consumes the exact saved plan. Its manifest binds source,
commit, config, generated inputs, backend, and plan hash. Root 02 also binds
upstream state metadata. Changes require a new plan. Locking protects individual
mutations; coordinate operators outside CI. Artifacts are sensitive and expire
after one day.

## Adopt version 2 after teardown

This change assumes the previous deployment was deprovisioned. Version 1 YAML
and environment-only state keys are rejected. This feature does not move or
delete old states; existing live deployments need a separately reviewed migration.

Deprovisioning retains buckets and KMS keys. Do not reuse their names with fresh
state without importing them into an owner stack. The supplied custom
`demo.yaml` now selects dev/demo and a fresh workspace bucket name.
Generated AWS names also include the workspace. Review these names before
provisioning. Retained cloud resources were not inspected or changed here.

For teardown, see [Deprovision an environment/workspace](DEPROVISIONING.md).
