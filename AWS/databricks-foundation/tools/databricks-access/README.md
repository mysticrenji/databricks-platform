# YAML permissions through Terraform

## Compute policies and warehouse wiring

The separate [compute runner](COMPUTE.md) deploys the existing engineering/ML
policies and analytics warehouse with persona group ACLs through root04 after
workspace entitlements. It needs no dataset/metastore target. Root05 keeps data
grant ownership and does not create compute. This ADR 0007 path supersedes the
older offline-only compute statements below for dev/demo. Warehouse creation can
start billable compute on a later authorized apply; development stays mocked.

## Workspace feature matrix before dataset access

For dev/demo, provisioning runs `01-infra → 02-account → 02-workspace-access → 04-workspace compute`.
Root 02 continues to own account groups and USER/ADMIN workspace assignments.
The separate workspace-only `02-workspace-access` root owns entitlements for those
four verified groups through `modules/databricks/workspace-entitlements`.
Its state key is `databricks/dev/demo/02-workspace-access.tfstate`.

| Persona | Workspace features | SQL features | Unrestricted clusters | Instance pools |
| --- | --- | --- | --- | --- |
| Admins | Enabled | Enabled | Enabled (admin capability) | Enabled (admin capability) |
| Engineers | Enabled | Enabled | Disabled | Disabled |
| Analysts | Disabled | Enabled | Disabled | Disabled |
| ML | Enabled | Enabled | Disabled | Disabled |

The matrix is declared in `platform/access/roles.yaml`; the principal registry maps
personas to the four groups. There is no consumer persona in this rollout.
Entitlements enable workspace features; they grant no dataset access, policy ACLs
or warehouse ACLs and create no compute. ADMIN remains privileged, and inherited
entitlements or other groups can widen effective access. Analyst USER assignment
is retained while its workspace feature entitlement is disabled.

`tools/databricks-access/terraform_entitlements.py render` is credential-free and
loads personas, principals and provisioning inputs without dataset requests or a
registered metastore target. Live `plan` verifies root 02 state outputs, managed
group/assignment identities and the live workspace before configuring features.
No users or memberships are created. Root 05 must not manage these entitlements.
Competing ownership requires a reviewed migration; no state is moved implicitly.

The provisioning workflow calls `environment-workspace-access.yml` after the
account job, on main only for both live planning and apply. Other branches run
credential-free matrix validation and mocked tests. On a fresh deployment, root 02 must finish its reviewed apply before
feature planning can read the workspace/group IDs. A plan-only run can plan the
feature layer only when root 02 already exists; it cannot plan every new dependent
layer before the first apply. Other workspaces/staging keep their existing path;
production remains configuration-only.

Feature apply is manual/main-only, consumes the exact unexpired saved plan from
the same run, and requires `ENVIRONMENT_YAML_APPLY_ENABLED=true` plus actual
required reviewers, self-review disabled and administrator bypass disabled on
`dev-demo-apply`. Retirement instead requires
`ENVIRONMENT_YAML_DESTROY_ENABLED=true` and confirmation `dev/demo`. No new opt-in
variable or secret is introduced. Tests never apply or destroy live resources.

Deprovision dev/demo retires this feature state before root 02 groups/assignments.
A preview-only run previews feature retirement and does not attempt the account
preview while the feature state is managed. Execution retires features, then runs
the existing account/infra teardown. The downstream-state guard also blocks direct
account/infra teardown while feature resources remain, even if CI is bypassed.
Root 05 grants and any live roots 03/04 still need their reviewed retirement first.
Regenerate saved plans after source changes.

Implements [ADR 0006](../../docs/adr/0006-yaml-terraform-permissions.md) for dev/demo.
Teams declare a persona and access to existing catalogs/schemas/tables. Python
validates platform authorization and renders Terraform variables. Terraform owns
account groups, workspace assignments/entitlements and direct group grants.

The first dev/demo workspace-access layer belongs to provisioning root 02:
`platform/terraform-inputs/dev/demo.02-account.json` creates `dev-demo-admins`
(workspace ADMIN), `dev-demo-engineers`, `dev-demo-analysts`, `dev-demo-ml` (USER).
All member maps are empty; identity administrators manage membership externally.
This layer is independent of data objects and the permissions target/metastore.
Run the existing environment provisioning workflow with dev/demo and review its
root 02 plan. Apply retains the provisioning approval/opt-in requirements.

The registry marks those four groups `lifecycle: terraform`. Root 05 only references
their verified group IDs for dataset grants; it does not create their groups,
assignments or persona entitlements. Offline validation checks their names/roles
against the provisioning JSON. Before live data planning, the runner verifies
root 02 group IDs and managed assignments, then checks live group identity.
A missing catalog still blocks the dataset phase; it does not block root 02.
Existing root 05 group ownership requires separately reviewed migration, never
automatic adoption or dual management. Regenerate saved plans after this change.

This workflow creates no catalogs, schemas, tables, users, memberships, storage,
metastore assignments or compute. Data objects must be provisioned separately.
Compute declarations/persona references remain in the offline preview but are not
deployed by the permissions renderer. Account-group membership stays with the IdP
or identity administrators. Workspace ADMIN does not imply catalog ownership.

## Configuration

Paths below are relative to this foundation:

| Input | Author/purpose |
| --- | --- |
| `platform/access/roles.yaml` | Platform: personas, exact packages and entitlements |
| `platform/access/principals/dev/demo.yaml` | Platform: workspace-prefixed groups; terraform bootstrap references or separately adopted create/external groups |
| `platform/access/resources/dev/demo.yaml` | Platform/data owners: approved existing objects, workload-to-group mapping and package limits |
| `platform/access/targets/dev/demo.yaml` | Verified account/workspace/metastore identity; active permits planning only |
| `platform/access/reviewers.yaml` | Review routing only; does not configure/enforce GitHub approvals |
| `workloads/<team>/dev-demo.yaml` | Team: persona and approved data_access requests |

The platform registry chooses the group; a team cannot nominate another principal,
raw privilege, owner, endpoint or compute setting. Reader/writer packages expand
centrally. Table grants add parent USE_CATALOG/USE_SCHEMA. Schema SELECT includes
future tables/views. Other groups, ownership and inheritance may provide wider
access, so removing a direct grant is not proof that all effective access ended.

The target IDs come from provisioning run38941131929 and live metastore check
run38959638081. Reprovisioning requires reviewed identity updates and a fresh plan.
A populated permissions state cannot be silently pointed at a different target.

## Offline commands

From the foundation directory:

```bash
python3 -m venv /tmp/databricks-access-venv
/tmp/databricks-access-venv/bin/pip install -r tools/databricks-access/requirements.txt
/tmp/databricks-access-venv/bin/python tools/databricks-access/access.py validate --environment dev --workspace demo
/tmp/databricks-access-venv/bin/python tools/databricks-access/access.py preview --environment dev --workspace demo
/tmp/databricks-access-venv/bin/python tools/databricks-access/terraform_entitlements.py render --environment dev --workspace demo --artifacts /tmp/workspace-feature-inputs
/tmp/databricks-access-venv/bin/python tools/databricks-access/terraform_permissions.py render --artifacts /tmp/permissions-inputs
/tmp/databricks-access-venv/bin/python -m unittest discover -s tools/databricks-access/tests -v
```

`terraform_entitlements.py render` emits `workspace-access.intent.json`, an offline
feature intent with no invented SCIM IDs. Its live `plan|apply|preview-destroy|destroy`
commands require `--state-bucket`, `--state-region` and `--artifacts`; destruction
requires `--confirm-environment dev/demo`. Use CI for reviewed execution.

`access.py preview` stays explicitly non-executable and contains no live diff.
`terraform_permissions.py render` emits `permissions.tfvars.json`: deterministic
workspace group definitions and unioned catalog/schema/table grants, with no data
object or compute creation inputs. Request ordering does not change resource keys.
Removing a workload updates the union; parents remain while another request needs
them. Empty data_access is supported. Workload authoring is documented in
[workloads/README.md](../../workloads/README.md).

## Terraform and CI

- `modules/databricks/workspace-access` reuses account-groups for new groups,
  checks external names against explicit SCIM IDs, and manages workspace entitlements.
- `modules/databricks/uc-permissions` manages one `databricks_grant` per
  principal/object pair. All workload contributions are combined before Terraform.
- `environments/dev/05-permissions` references root 02 bootstrap groups for grants;
  its workspace-access module handles only separately adopted create/external groups.
  It never runs roots 01-04 or changes bootstrap assignments/entitlements.
  State key: `databricks/dev/demo/05-permissions.tfstate` in TF_STATE_BUCKET/REGION.

`.github/workflows/environment-validation.yml` (`Validate Databricks platform`)
runs both Python suites once, offline access validation/preview and rendering,
Terraform formatting/validation, mocked module/root tests and generated-input
tests without cloud credentials. It is the only automatic workflow and covers
foundation and workflow changes on pull requests and main pushes. The module/root
lockfiles pin the provider version.

`.github/workflows/databricks-permissions.yml` (`Databricks permissions and diagnostics`)
is manual-only on main. Choose `operation=plan` (the default) to plan permissions;
leave `deploy=false` for a plan only. Runs on other refs are skipped. PR code never
receives deployment credentials. Live planning is explicit because the demo may
be deprovisioned between uses; ordinary changes run offline CI only.

Plan uses existing `dev-demo-plan` variables AWS_DEPLOYMENT_ROLE_ARN,
TF_STATE_BUCKET, TF_STATE_REGION, DATABRICKS_ACCOUNT_ID, DATABRICKS_CLIENT_ID and
secret DATABRICKS_CLIENT_SECRET. AWS uses OIDC; Databricks uses OAuth M2M. The
current diagnostic/provisioning identities are reused; separate least-privilege
identities remain an operator configuration task. Install requirements-live.txt.

The runner verifies AWS identity, account/workspace/metastore binding, known
legacy Terraform ownership, account group identities, object existence and direct
ACLs. Missing/forbidden reads fail clearly. It refuses matching-name/grant adoption;
imports require a separately reviewed operation. See [OWNERSHIP.md](OWNERSHIP.md).
It reads legacy states temporarily for ownership checks, never to discover the
workspace URL, and never uploads those state files.

Manual `operation=plan`, `deploy=true` on main plans first, then the dev-demo-apply environment gates
application of that exact run's plan. Before enabling apply, configure:

1. dev-demo-apply with matching backend/account/identity values and credentials.
2. Required reviewers, self-review disabled and administrator bypass disabled.
   The environment currently lacks these protections, so the runner blocks apply.
3. Environment variable DATABRICKS_PERMISSIONS_APPLY_ENABLED=true only after
   reviewing the existing-object/ownership baseline and the saved plan.
4. Repository branch review/rules appropriate for platform and dataset owners.
   Reviewer YAML is informational; this workflow does not claim two-party checks.

The plan is bound to commit/source/input/target/backend and legacy-state hashes,
expires after24 hours, and is checked again before apply. Terraform checks its own
state freshness. Plans/manifests are retained as restricted repository artifacts
for one day; no state files or credentials are uploaded. The same target concurrency
group serializes provisioning, access and deprovisioning. No apply runs as part of
tests or a branch push, and this change does not enable opt-in or modify GitHub settings.

Plans containing data-object/compute/membership resource types, group/assignment/
entitlement deletion or replacement, or ADMIN removal are rejected. Normal grant
revocations remain supported. Group retirement/import/migration are separate
operator operations. Existing deprovisioning refuses managed or unreadable
permissions state; retire permissions before destroying the workspace.

Only dev/demo is supported initially. UC scopes live in a metastore: another
workspace must not manage the same principal/object pair. Catalog workspace
bindings stay with the object owner; this workflow does not establish isolation.

## Manual live diagnostics

Run `Databricks permissions and diagnostics` on main with `operation=diagnostics`,
`deploy=false`, and `workspace_id`/`workspace_url` from the current dev/demo
provisioning outputs. No created workspace IDs or URLs are hardcoded in the workflow.
It verifies AWS OIDC using the deployment role from `dev-demo-plan`, then runs
`identity_check.py` to verify account/workspace identity and OAuth access. Set
`check_metastore=true` to also discover the assignment and verify summary visibility.
Diagnostics do not produce or apply a Terraform plan. Discovery alone does not
approve a metastore or grant scope for Terraform ownership.

The standalone AWS OIDC and Databricks identity workflows have been folded into
this operation. Provision and deprovision remain separate manual entry points;
their four reusable workflows preserve root ordering and deployment/retirement gates.

## Single-admin policy for dev/demo provisioning

Dev/demo provisioning supports the private demo repository without required
GitHub environment reviewers. An administrator must manually dispatch provisioning
on main with `deploy=true`, `confirm_environment=dev/demo` and
`ENVIRONMENT_YAML_APPLY_ENABLED=true` in `dev-demo-apply`. The preflight and each
root/feature apply verify administrator permission for the initiating and rerunning
actors using GitHub's read-only API. Each apply still consumes its same-run saved
plan; no backend, identity, ownership or source binding is relaxed.

The read-only `terraform_entitlements.py check-approval --confirm-environment dev/demo
--artifacts /tmp/approval-check` checks this policy without AWS states or
Databricks/Terraform. It requires manual-main GitHub context, `GITHUB_REPOSITORY`,
`GITHUB_ACTOR`, `GH_TOKEN`, the apply opt-in and exact target confirmation.
See [run instructions](../environment/README.md#single-admin-devdemo-deployment).
Start a fresh provisioning run after merging source changes to main.

The exception also covers dev/demo feature retirement and account/infra teardown.
Use a manual main run by verified administrator actors, execute_destroy=true,
ENVIRONMENT_YAML_DESTROY_ENABLED=true and exact dev/demo confirmation. The apply
opt-in does not authorize retirement. Feature retirement still uses the bound,
unexpired same-run saved plan; storage purge retains its separate confirmation and
all existing retention/inventory/empty-state guards. See the
[deprovisioning guide](../environment/DEPROVISIONING.md#single-admin-devdemo-deprovisioning).
Root05 dataset permissions and other targets retain their existing reviewer
protection and opt-ins.
