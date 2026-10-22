# Terraform permissions ownership

ADR 0007 wires persona compute through the existing root04 state and modules.
Root04 owns policy/warehouse objects and their whole-object ACLs; root02 groups,
feature entitlements and root05 data grants retain their owners. The compute
runner rejects unrelated/unbound root04 ownership and known competing object/ACL
owners rather than silently adopting names or migrating state. See [COMPUTE.md](COMPUTE.md).

The active decision is [ADR 0006](../../docs/adr/0006-yaml-terraform-permissions.md).
Root05-permissions owns only its declared account groups, workspace assignments,
entitlements and per-principal direct UC grants. No catalog/schema/table,
metastore assignment, membership or compute ownership moves to this flow.

The Python runner checks known02/03/04 states in the selected backend and root02
supplemental groups before planning or applying. Whole-object databricks_grants
blocks adoption of any principal on that object; per-principal databricks_grant
blocks only the same principal/object pair. Existing groups or direct grants need
reviewed import, never matching-name adoption. External lifecycle explicitly
references a registered group ID; it does not transfer group/membership lifecycle.

Existing root05 state must match the registered account/workspace/metastore.
Other states/repositories and out-of-band administrators are not discoverable
through these checks: operators must ensure one owner for every selected scope.
Live object reads and known state checks are evidence, not an exhaustive inventory.
Do not remove legacy resource configuration and apply if it would delete resources.
Group/assignment/entitlement retirement and ADMIN removal stay outside normal apply.

The repository snapshot below documents the earlier API proposal and is retained
for its legacy-owner evidence. Its future Python ownership transfers and API
inventory prerequisites have been superseded by Terraform state and ADR0006.

---

# Ownership snapshot and adoption prerequisites


## Workspace features before dataset access

Dev/demo provisioning now runs `01-infra → 02-account → 02-workspace-access`.
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
before account groups; a dev/demo dry run previews feature retirement only.
Other targets are unchanged. No implicit adoption, state migration or live apply
is performed during development. See the [feature runner guide](README.md).


## Workspace-access amendment (2026-10-17)

Provisioning root 02 retains the four dev/demo bootstrap account groups and their
workspace assignments: admins ADMIN, engineers/analysts/ML USER. Its supplemental
JSON explicitly configures them with empty member maps; membership stays external.
The principal registry uses `lifecycle: terraform`. Root 05 references these groups
for dataset grants and excludes their assignments/entitlements from its managed
workspace-access inputs. The separate `02-workspace-access` root now owns bootstrap
persona entitlements; compute remains outside this rollout.

Offline validation checks names/roles against provisioning inputs. Live data planning
requires matching root02 account_group_ids outputs, managed group records and exact
target-workspace assignments, then confirms the live account IDs. Competing owners
in03/04/05 are rejected. No names are silently adopted or state moved. Existing05
group ownership needs a separately reviewed migration before this amendment.

Root02 provisioning does not load dataset requests or depend on the access metastore
target; a missing catalog blocks only the later data workflow. Deprovision still
requires retiring root05 grants before root02 assignments/groups and infrastructure.
The historical snapshot below is superseded by this amendment for bootstrap identity
ownership only. No live changes were made while implementing this amendment.

Snapshot: 2026-10-16, repository configuration only. No live state, Databricks
permissions, AWS resources or GitHub approval settings were inspected. The new
tool is offline; none of the resources below have moved ownership.

## Current repository owners

| Source | Current configured ownership | Future boundary |
| --- | --- | --- |
| `environments/dev/02-account/main.tf`, `modules/databricks/account-groups/main.tf` | Account groups, memberships, delegated managers, workspace permission assignments when configured | Transfer only explicitly adopted groups/assignments; membership remains external |
| `environments/dev/02-account/outputs.tf` | Exports workspace ID/URL and account group IDs | Supply minimal reviewed identity outputs to target registry |
| `environments/dev/03-data-access/main.tf` | Metastore/assignment, storage integration, generic and composed catalogs/grants | Keep object/storage lifecycle in Terraform; transfer whole adopted grant-resource scopes |
| `modules/databricks/catalogs/main.tf` | Catalog/schema/volume objects plus one authoritative grant resource per nonempty grant map | Empty map currently means unmanaged, not revoke-all; release live grant resources without destroy |
| `modules/databricks/data-access` | UC IAM/credentials/locations, optional learning catalog and operations resources/grants | Keep storage integration and unrelated grants; reject overlapping generic/composed ownership |
| `environments/dev/04-workspace/main.tf` | Local identities, profiles, policies, warehouses, jobs | Keep jobs/profiles/files; transfer only adopted identities/compute/ACLs |
| `modules/databricks/cluster-policies` | Policies, optional file upload and authoritative ACLs | File/init-script ownership must not move implicitly with policy adoption |
| `modules/databricks/sql-warehouses` | Warehouses and authoritative ACLs | Transfer IDs and whole adopted ACL ownership explicitly |

Root 02 defaults `account_groups = {}` but its local `terraform.tfvars` includes
legacy groups. Root 03's local tfvars names `dev_analytics` and `dev_operations`,
with developer/reader grants and init-script/log-volume dependencies. Those are
not the new `dev_demo` catalog and four `dev-demo-*` group declarations.
Root 04's local tfvars configures compute policies and init-script upload;
`warehouses = {}` there does not disable ownership in other configurations.
Do not infer absence of deployed resources from empty variable defaults.

Environment CI currently runs roots 01/02 only with explicit rendered and
supplemental inputs. It does not run local root tfvars. The demo supplemental
JSON files are empty; the new access YAML is not fed to Terraform or the adapter.
Neither demo data objects nor API groups have been provisioned by this feature.

Root 03 still has region/dev-specific naming and no completed namespace-aware
handoff for the new access path. Catalog workspace bindings are not yet wired
for this delivery. A separate Terraform state or workspace label does not isolate
UC data in a shared metastore. These are prerequisites, not claims of readiness.

## Before a live planner/apply rollout

1. Inspect configured inputs and actual states/resources for the selected target.
   Record every resource ID, grant/ACL owner and external membership source.
2. Bind reviewed workspace ID/URL/account/metastore outputs to the target registry.
   Verify live identity and approved catalog isolation/bindings. Preserve a working
   deployment identity and independent recovery administrator.
3. Implement an explicit adoption registry plus checks that block overlapping raw
   Terraform/supplemental inputs. The current `active` flag is target metadata,
   not an adoption switch or permission to apply.
4. For existing resources, review a Terraform ownership release without resource
   deletion and an API inventory import of the same IDs/ACL baseline. Do not just
   delete a block and apply: that can destroy resources. A Terraform
   `databricks_grants` resource owns a whole securable ACL, so releasing only one
   principal while leaving that authoritative resource is invalid.
5. Test old callers and demonstrate plans do not recreate adopted resources.
   Do not claim an offline desired preview detects ownership conflicts or live drift.
6. Complete metastore-wide grant union, durable inventory, lock/journal, stale-plan
   checks and the API-inventory deprovision blocker before exposing write commands.

For a fresh deployment: Terraform 01/02 → future API group/assignment phase →
Terraform 03 objects/bindings → future API grants/compute phase. Terraform 04 may
manage nonoverlapping resources only. Existing deprovisioning must eventually
retire API contributions before destroying workspace/infrastructure; until that
guard exists, no access apply workflow is enabled.

This file provides repository evidence for P01. It is not a completed live
inventory, migration, state-operation authorization or adoption implementation.
