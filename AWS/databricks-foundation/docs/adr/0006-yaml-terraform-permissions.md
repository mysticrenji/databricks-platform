# ADR 0006: YAML requests compiled to Terraform permissions

> ADR 0007 (2026-10-19) extends the previous offline-only compute decision:
> dev/demo now deploys persona policies, the analytics warehouse and compute ACLs
> through the existing root04 state after workspace entitlements. It retires
> compute before features/groups/infra. Root05 still manages data permissions only.
> See [ADR 0007](0007-persona-compute-wiring.md) and the compute runner guide.

- Date: 2026-10-16
- Status: Accepted by the user; implementation targets dev/demo
- Supersedes: ADR 0005's proposed Python write/reconciliation engine

## Decision


### Workspace feature matrix before dataset access

For dev/demo, provisioning runs `01-infra → 02-account → 02-workspace-access`.
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

Feature apply is manual/main-only and consumes the exact unexpired saved plan from
the same run. The 2026-10-18 single-admin provisioning amendment requires
`ENVIRONMENT_YAML_APPLY_ENABLED=true` in `dev-demo-apply`, `deploy=true` and exact
confirmation `dev/demo`. The initiating and rerunning actors must have repository
admin permission, verified using GitHub's read-only API before infra creation and
again before each root apply. Required environment reviewers, prevention of
self-review and disabled administrator bypass are not prerequisites for this
dev/demo provisioning exception: the private demo repository's plan does not
provide required environment reviewers. This policy intentionally permits one
administrator to authorize deployment. Other environments/workspaces and root05
permissions retain the existing reviewer requirements. The 2026-10-18
deprovisioning extension applies the administrator/manual/main checks to feature
retirement and account/infra teardown without required environment reviewers.
Retirement requires execute_destroy=true, `ENVIRONMENT_YAML_DESTROY_ENABLED=true`
and confirmation `dev/demo`, independently of provisioning opt-in. Optional storage
purge retains a separate matching confirmation and the reviewed inventory and
fresh empty-state checks. No new opt-in
variable or secret is introduced. Tests never apply or destroy live resources.

Deprovision dev/demo retires this feature state before root 02 groups/assignments.
A preview-only run previews feature retirement and does not attempt the account
preview while the feature state is managed. Execution retires features, then runs
the existing account/infra teardown. The downstream-state guard also blocks direct
account/infra teardown while feature resources remain, even if CI is bypassed.
Root 05 grants and any live roots 03/04 still need their reviewed retirement first.
Regenerate saved plans after source changes.

### Workspace-access layer (2026-10-17)

Provisioning root 02 owns the first dev/demo access layer immediately after
workspace creation: `dev-demo-admins` receives workspace ADMIN; engineers,
analysts and ML receive USER. The four names are declared in
`platform/terraform-inputs/dev/demo.02-account.json`; all member maps are empty.
Membership stays external and existing administrator/recovery access is preserved.
This phase requires no catalog, metastore registration in the access target,
dataset declaration or compute. The separate `02-workspace-access` root follows
workspace/group provisioning and configures persona entitlements before data grants;
workspace defaults and other memberships still apply and ADMIN remains privileged.

The principal registry marks these groups `lifecycle: terraform`. Root 05 treats
them as references and deploys only their dataset grants, after data objects exist.
Its runner binds them to root 02's exported IDs and managed group/assignment records,
verifies the expected workspace roles, and rejects competing ownership in other
states. It checks the live group IDs again before planning/applying data access.
Their assignments and entitlements are excluded from the root 05 workspace-access
module. Separately adopted create/external groups retain that module's contract.
Never let the same group/assignment be managed by both roots.

This amendment supersedes the original combined group/data bootstrap below for
the four demo groups. A missing catalog may block data permission planning but
must not block workspace provisioning/group assignment. A populated root 05 state
that already owns those groups requires separate reviewed ownership migration;
do not move state implicitly. No apply, import or remote changes run during tests.

Teams declare a persona and access to existing data objects in workload YAML.
Python validates the platform-approved persona/group/dataset contract, expands
reader/writer packages and parent usage, unions requests per principal/object,
and renders deterministic Terraform variables. Terraform creates workspace-specific
account groups, assigns USER/ADMIN workspace access, manages group entitlements
and reconciles direct Unity Catalog grants. Python SDK calls are read-only checks.

Catalogs, schemas, tables and views are created through a separate process.
This permissions flow never creates them or manages their owners. It also creates
no users, memberships, storage, metastore assignments, clusters, warehouses or
policies. Existing foundation modules remain available to their existing callers;
the new workflow never calls the object-creation roots. Compute YAML remains an
offline preview and is outside this deployment contract.

## Implementation and ownership

- `modules/databricks/workspace-access` reuses account-groups for created groups,
  verifies registered external groups by name and SCIM ID, and adds workspace
  assignments/entitlements without touching membership.
- `modules/databricks/uc-permissions` uses `databricks_grant` per principal/object,
  preserving other principals. Existing authoritative `databricks_grants` ownership
  of a whole object is incompatible; transfer it explicitly before adoption.
- `environments/dev/05-permissions` composes these modules with account/workspace
  provider aliases for separately adopted identities, and references Terraform
  bootstrap identities from root 02 for data grants. No workspace is created here.
- State is `databricks/dev/demo/05-permissions.tfstate` in the configured state
  bucket, with S3 lockfile locking. It is separate from roots 01-04.

Each direct principal/object scope has one owner across all states/workspaces in
the metastore. Version one accepts dev/demo only and workspace-prefixed groups.
External groups must also follow that namespace. Extending the targets requires
an explicit shared-scope ownership design, not simply copying a state file.
Workspace names do not isolate Unity Catalog: catalog workspace bindings remain
the object owner's responsibility and are not modified by this flow.

The runner reads known legacy states 02/03/04 and rejects conflicting group or
grant ownership. It also checks root02 supplemental group declarations, refuses
silent adoption of existing names or direct grants, and rejects retargeting its
own populated state. Import/release existing resources only through a separately
reviewed Terraform operation. State contents are temporary and never uploaded by
this workflow. These checks cannot discover ownership in unrelated external states.

## CI and lifecycle

PR CI has no cloud credentials: strict Python tests, rendering, module tests and
an end-to-end generated-input Terraform test all use mocked providers. Manual
main-only planning reads actual identities, assignment, groups, data objects
and direct grants before planning. API errors fail, including missing objects;
the workflow does not create prerequisites or silently skip requests.

Manual main-only apply consumes the plan from that same workflow run. Bind it to
the commit, source/input hashes, target/backend identities, legacy-state snapshots
and a plan hash with 24-hour expiry. Recheck live identities/ownership before
apply; Terraform rejects a stale saved plan against its own state. Use the same
target concurrency group as provisioning/deprovisioning and do not cancel mutations.

Apply additionally needs `DATABRICKS_PERMISSIONS_APPLY_ENABLED=true` and an actual
GitHub Environment requiring reviewers, self-review disabled, and administrator
bypass disabled. The current environment lacks these protections, so apply remains
blocked. Reviewer YAML is routing information, not an enforced two-party review
system; branch review/rules remain operator configuration.

Plans are restricted to group, workspace assignment, entitlement and grant resource
types. Group/assignment/entitlement deletion or replacement and ADMIN downgrades
are blocked pending separate retirement/migration review. Removing a workload may
revoke only its unioned direct grants; inherited access can remain. Terraform owns
revocation and drift reconciliation, removing the need for a separate Python write
inventory. Deprovisioning blocks on managed or unreadable permissions state before
removing the workspace. Terraform permissions teardown must be reviewed separately.

No live apply, migration/import, object creation or GitHub settings change is part
of implementing and testing this workflow.
