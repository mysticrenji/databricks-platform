# Persona compute deployment

`terraform_compute.py` compiles `platform/compute/dev.yaml` and persona mappings
in `platform/access/roles.yaml` into the existing root04 Terraform modules.
Root02 account groups remain the principals; membership stays external.

| Group | Cluster policy | Analytics SQL warehouse |
| --- | --- | --- |
| `dev-demo-admins` | Workspace admins already manage policies | `CAN_MANAGE` |
| `dev-demo-engineers` | `engineering-standard`: `CAN_USE` | `CAN_USE` |
| `dev-demo-analysts` | None | `CAN_USE` |
| `dev-demo-ml` | `ml-standard`: `CAN_USE` | `CAN_USE` |

The policies enforce approved runtime/node allowlists, one to two workers,
20-minute automatic termination and one cluster per user per policy. ML uses
CPU ML runtime with dedicated access mode. Pools, instance profiles, containers,
init scripts and flexible fallback nodes are disabled by the rendered rules.
The analytics warehouse is Small, non-serverless, limited to one cluster, with
15-minute auto-stop. Policy creation starts no clusters; **a later SQL warehouse
apply can start billable compute**. Tests never start compute or run queries.

Unrestricted cluster creation remains disabled for engineers/analysts/ML by the
separate entitlement matrix. Default Personal Compute access, inherited groups,
workspace ADMIN and existing cluster ACLs can widen effective access; this runner
does not silently manage those defaults. Warehouse access does not grant data
access. Root05 remains responsible for approved Unity Catalog grants.

## Ownership

Policies, the warehouse and their authoritative ACLs belong to
`environments/dev/04-workspace`, state `databricks/dev/demo/04-workspace.tfstate`.
No new state or competing owner is introduced. Root02 retains groups/assignments;
`02-workspace-access` retains persona entitlements. No users, memberships, jobs,
files, instance profiles or data objects are created by the compute runner.

The dev/demo runner sets `read_data_access_state=false`, with null volume paths
and no init-script upload. It needs no datasets, workload files, registered
metastore target or root03 state. Legacy root04 callers default to reading root03;
UC log/init-script volumes still require that dependency. Local tfvars, backend
files and Terraform environment overrides never enter the isolated runner.

Live preflight verifies AWS/OAuth identity, root02 group IDs and workspace roles,
the applied feature matrix, runtime/node availability and existing object IDs.
Terraform rechecks the expected workspace ID/URL and group IDs against root02.
Matching names do not authorize adoption: existing objects must match root04-owned
IDs. Unknown/unbound root04 ownership, unrelated resources, deposed instances,
changed group bindings or known competing object/ACL owners require reviewed
import/migration. Other repositories and external operators remain outside these
known-state checks. No state is migrated implicitly.

## Offline validation

From the foundation directory:

```bash
python3 tools/databricks-access/terraform_compute.py render --artifacts /tmp/compute-inputs
python3 -m unittest discover -s tools/databricks-access/tests -v
python3 -m unittest discover -s tools/environment/tests -v
terraform -chdir=environments/dev/04-workspace init -backend=false -input=false -lockfile=readonly
terraform -chdir=environments/dev/04-workspace test -no-color
terraform -chdir=environments/dev/04-workspace test -no-color -test-directory=generated-tests -var-file=/tmp/compute-inputs/compute.tfvars.json
```

Render writes `compute.tfvars.json` and `compute.intent.json`, without fabricated
workspace/group IDs or cloud calls. These are inputs, not a live or executable
plan. PR CI runs Python and mocked Terraform tests, including generated inputs.

## Provision

After review and merge, run **Provision environment YAML** on `main` with
dev/demo, `deploy=true` and `confirm_environment=dev/demo`. Retain the existing
matching plan/apply backend/identity variables and OAuth secret, with
`ENVIRONMENT_YAML_APPLY_ENABLED=true` in `dev-demo-apply`.

The sequence is `01-infra → 02-account → 02-workspace-access → 04-workspace compute`.
Fresh compute planning requires completed root02 and feature applies; plan-only
runs cannot invent those IDs. Live planning rejects unavailable runtime/node IDs;
update approved YAML and create a fresh plan when required. Other workspaces,
staging and production are not enabled by this compute feature.

The reusable `environment-compute.yml` workflow is manual/main/dev/demo only.
Apply rechecks administrator permission, operation-specific opt-in and target
confirmation, then applies the exact same-run saved plan. Its 24-hour manifest
binds commit/source, inputs, backend and all six state snapshots. Drift or changed
plan bytes requires a new plan. Normal plans reject deletion/replacement or
unexpected managed addresses. Only plan/manifest artifacts are uploaded for one
day; no state or credentials are uploaded. No live apply runs during development.

## Retire

Deprovision orders `04-workspace compute → 02-workspace-access → 02-account → 01-infra`.
Compute retirement uses a saved destroy-only plan and the independent
`ENVIRONMENT_YAML_DESTROY_ENABLED=true` opt-in, manual main run by a verified admin,
and exact `dev/demo` confirmation. Apply opt-in cannot authorize destruction.
Empty root04 state produces a bound no-op without SDK/Terraform execution;
unrecognized root04 ownership blocks retirement. Direct entitlement retirement
also rejects managed root04 state; direct account/infra teardown retains its guard.

Preview-only dev/demo deprovision previews compute and feature retirement, then
stops before account/infra. Root03/root05 data resources still need their separate
retirement first. Storage retention, separately confirmed permanent purge,
fresh all-six-state empty checks and backend-history/KMS preservation remain
unchanged. See [deprovisioning](../environment/DEPROVISIONING.md).
