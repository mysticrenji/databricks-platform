# Repository guidance

## Persona compute wiring

ADR 0007 extends the prior offline-only compute boundary for dev/demo. The separate
terraform_compute.py render|plan|apply|preview-destroy|destroy runner compiles
platform/compute/dev.yaml and persona mappings into existing root04 policy and
warehouse modules, using databricks/dev/demo/04-workspace.tfstate. Never duplicate
ownership in root05 or the entitlement state. Keep root02 groups/assignments,
external membership, feature entitlements and data grants separate. Analysts get
warehouse CAN_USE and no cluster policy; engineers/ML get their declared policy
CAN_USE. Admins retain workspace-admin policy access and warehouse CAN_MANAGE.

Compute loading/render is credential-free and independent of datasets/metastore
registration. Live planning verifies root02/live identities, applied feature
matrix, runtime/node availability and known object/ACL ownership. Do not adopt
matching names, drop unrelated root04 resources or migrate ownership implicitly.
The runner sets read_data_access_state=false only with null UC volume paths and
no init upload. Existing root04 callers default to the root03 dependency.

Provision compute after features; deprovision compute before features/groups/infra.
Preview-only dev/demo deprovision previews compute and feature retirement, then
stops before account/infra. Direct feature retirement rejects managed root04;
direct account/infra teardown retains its root04 guard. Manual/main-only dev/demo
execution requires verified admins, separate apply/destroy opt-ins, exact dev/demo
confirmation and a same-run plan with source/input/backend/all-six-state binding
and 24h expiry. Reject unexpected resource addresses and normal deletion/replacement.
Purge confirmations, retention and KMS/backend preservation remain unchanged.

PR CI runs both Python suites and mocked policy/warehouse/root04 tests, including
generated inputs. Never live-plan/apply/destroy or start compute in development/tests.
A later authorized warehouse apply can start billable compute. Root05 and other
targets remain separately gated. See tools/databricks-access/COMPUTE.md; this
section supersedes older offline-only compute references below for dev/demo only.

## Knowledge graph

When the user types `/graphify`, invoke the `graphify` skill before doing any
other work.

## Environment YAML adapter

Deprovisioning is documented in `docs/adr/0003-github-actions-deprovisioning.md`
and `tools/environment/DEPROVISIONING.md`. The manual workflow destroys root 02
before 01 with the original backend/input bindings. It retains all S3 and KMS
resource addresses by backing up state and releasing their Terraform ownership;
preview does this only on a local state copy. Reject live downstream root 03/04
states, changed preview bindings, or missing destroy opt-in/confirmation. Never
run a live destroy during development or tests.

Optional decommission storage purge requires `purge_storage=true`, destroy opt-in,
and separate matching `confirm_purge_storage=environment/workspace`. Retention is
the default. Preview inventories only configured buckets recorded in infra state;
never infer detached ownership from names. Bind the inventory and content digests
to the reviewed preview. Purge runs only after successful infra teardown and a
fresh empty-state check for all six roots, deletes all versions/delete markers
and incomplete uploads, and verifies bucket absence. Fail on incomplete cleanup.
Always preserve the backend state bucket/history and KMS resources. Retain preview
artifacts for explicit recovery after partial purge; never restore old full state.
Test storage cleanup with mocked S3 only; no live purge during development/tests.

Environment provisioning is documented in `docs/adr/0002-environment-yaml-provisioning.md`
and `tools/environment/README.md`. Keep validation credential-free. Templates
are organized under `platform/environments/{dev,staging,production}`. Version 2
runs dev and staging roots 01 and 02 only; production templates must remain
configuration-only. ADR 0004 defines the current environment/workspace identity:
`workspace.name` is required, state keys use `databricks/<environment>/<workspace>/`,
GitHub Environments use `<environment>-<workspace>-plan`/`-apply`, and AWS names
include both identifiers. Reject mismatched targets/keys. The prior deployment
was deprovisioned before this fresh namespace; do not migrate old state silently.
Root 02 must verify root 01's exported identity. Retained S3/KMS resources require
separate ownership/import and must not be assumed deleted.
Use strict `schema.json` plus Python semantic validation, and keep rendered
inputs isolated from local tfvars and environment overrides. Test with
`python3 -m unittest discover -s tools/environment/tests -v` from this directory.
Retain optional existing inputs explicitly in `platform/terraform-inputs/` before adoption;
do not silently drop group memberships or enabled resources. CI applies require
configured environment approval and explicit opt-in, except the dev/demo
single-admin policy below; do not apply during tests.

Single-NAT egress can share one private route table across workspace subnets.
VPC endpoint validation must accept that table while still requiring interface
endpoint subnets in at least two availability zones.

## Purpose and layout

Administrator-owned inputs live in `platform/`: provisioning YAML under
`platform/environments/`, compute definitions under `platform/compute/`, personas
and registries under `platform/access/`, and supplemental JSON under
`platform/terraform-inputs/`. The latter adds optional inputs to rendered Terraform
values; it contains no Terraform code or state and cannot override YAML-owned
settings. Do not add a generic nested config folder. Consumer declarations remain
in foundation-local `workloads/`. Terraform execution code stays in top-level
`environments/` and reusable code in `modules/`. Read `platform/README.md`.
Update helper defaults, workflow paths, tests and documentation together when
moving inputs. Existing GitHub ENVIRONMENT_CONFIG_PATH variables need the new
repository-relative path; never migrate state or change workspace identity just
because a folder moved. Regenerate saved plans/previews after source changes.

The active permissions design is [ADR 0006](docs/adr/0006-yaml-terraform-permissions.md).
User decision: Terraform manages workspace-specific account groups, workspace
assignments/entitlements and grants on EXISTING catalogs/schemas/tables. Python
validates/expands YAML, renders Terraform inputs and performs read-only SDK checks.
Never create data objects, users, memberships or compute in this workflow. Do not
implement ADR 0005's superseded Python write engine or inventory. Existing object
creation modules/roots keep their existing ownership and callers.

First workspace-access layer: root 02 provisioning owns the four dev/demo bootstrap
groups/assignments through `platform/terraform-inputs/dev/demo.02-account.json`:
admins ADMIN; engineers/analysts/ML USER. Empty member maps leave membership external.
It needs no dataset/compute or access-target prerequisite. The principal registry
marks them `lifecycle: terraform`; root 05 must reference verified root 02 group IDs
and must not manage their assignments/entitlements. Validate name/role parity offline
and root02 output/resource/live identities before dataset planning. Reject duplicate
ownership and require reviewed migration for any existing05 group ownership.
Bootstrap persona entitlements now belong to the separate workspace-only root
`environments/dev/02-workspace-access`, state
`databricks/dev/demo/02-workspace-access.tfstate`, using `workspace-entitlements`.
Run after 02 account apply and before datasets; never combine workspace creation
and workspace-provider resources in the same state. Matrix source roles.yaml:
admins workspace/SQL/both compute capabilities true; engineers/ML workspace/SQL
true with both compute capabilities false; analysts workspace false, SQL true,
both compute capabilities false. The entitlement layer adds no consumer persona;
ADR0007's separate root04 layer now adds compute ACLs.
The feature runner loads only personas/principals/provisioning inputs and verified
root02 outputs/live identities; no datasets or metastore target prerequisite.
Root05 must not own bootstrap entitlements. Reject competing owners; never migrate
state implicitly. Defaults/other groups can still widen effective access.
Provision CI adds a main-only dev/demo feature job after account; live feature
planning/apply never run on untrusted refs. Fresh feature planning
requires completed root02 apply. Feature apply is main-only with exact same-run
saved plan, ENVIRONMENT_YAML_APPLY_ENABLED and the single-admin provisioning
checks below. Retirement uses the same administrator/manual/main checks,
ENVIRONMENT_YAML_DESTROY_ENABLED and dev/demo confirmation, without reviewers.
Deprovision retires feature state before root02 groups and root01 infrastructure;
preview-only dev/demo previews compute and feature retirement. Direct teardown also checks
feature state. Other targets remain unchanged, production configuration-only.
This amendment supersedes the combined bootstrap in ADR0006.

Dev/demo provisioning and deprovisioning use a single-admin exception because the private demo
repository's GitHub plan does not support environment reviewers. Require manual
workflow_dispatch on main, deploy=true, ENVIRONMENT_YAML_APPLY_ENABLED=true from
dev-demo-apply and exact confirm_environment=dev/demo. Verify the initiating and
rerunning actors have repository admin permission through the read-only GitHub API.
Check this before infra creation and again before each root/feature apply using
the exact same-run saved plan. `terraform_entitlements.py check-approval` now
checks this policy without AWS state, Databricks credentials or Terraform.
No required-reviewer/self-review/admin-bypass configuration is required for this
exception. Deprovisioning requires manual workflow_dispatch on main by verified
admin actors, execute_destroy=true, ENVIRONMENT_YAML_DESTROY_ENABLED=true and
confirm_environment=dev/demo. Check these before feature retirement and before
account/infra destruction, including empty-state no-ops. Apply opt-in cannot
authorize destruction. Optional purge still requires purge_storage=true plus
separate confirm_purge_storage=dev/demo, bound preview/inventory checks, successful
teardown and all six states freshly verified empty. Keep backend history and KMS.
Other targets and root05 permissions retain existing approval requirements.
Never apply, destroy or purge live resources in tests.

`tools/databricks-access/access.py validate|preview` stays offline. The separate
`terraform_permissions.py render|plan|apply` drives root `environments/dev/05-permissions`
and modules `workspace-access`/`uc-permissions`. It uses state
`databricks/dev/demo/05-permissions.tfstate`; do not combine it with legacy roots.
The registered workspace/metastore IDs were verified by CI. Active target means
read-only planning eligibility, not apply authorization. Production/staging and
other workspace targets remain blocked by the strict loader.

Keep platform-owned personas/principals/resources/reviewer routing in platform/
and team requests in workloads/. Union all requests per group/object before
rendering, retain parent usage, and preserve stable scope keys. Group membership
stays external. Do not silently adopt matching names/grants or overlap whole-object
`databricks_grants` with per-principal grants. Read OWNERSHIP.md and the permissions
runner README before changing ownership. Shared-metastore scopes have one owner.

PR CI stays credential-free and uses mocked providers; the consolidated
environment-validation.yml runs both Python suites once and preserves all mocked
module/root and generated-input tests. Permissions planning and optional read-only
AWS/Databricks diagnostics run only through manual dispatch on main in
databricks-permissions.yml; diagnostics take current provisioning workspace ID/URL
inputs. No live checks run automatically on push. Apply
is manual/main-only, requires the exact unexpired saved plan, explicit
DATABRICKS_PERMISSIONS_APPLY_ENABLED=true and an actual protected environment with
required reviewers, self-review disabled and administrator bypass disabled. Do not
enable or run live apply during development. Group deletion/ADMIN downgrade needs
separate retirement/migration review. Deprovision must check permissions state.

Run the Python access and environment suites, mocked tests for changed modules/root,
and actionlint for workflows. The existing identity_check.py live diagnostic stays
read-only; discovery does not adopt a metastore or modify assignments. Root05 does
not create compute; ADR0007's separate root04 runner now deploys compute YAML.

This repository provisions Databricks on AWS with Terraform. Keep reusable AWS
modules under `modules/aws` and Databricks modules under `modules/databricks`.
The data-access composition lives under `modules/databricks/data-access` and
calls reusable AWS IAM modules from `modules/aws` where needed.

```text
modules/
  aws/
    vpc/ subnets/ egress/ security-groups/ vpc-endpoints/
    IAM-roles/ kms/ root-storage/ kinesis/ observability/ data-storage/ uc-storage-roles/
  databricks/
    account-configuration/ workspace/ account-groups/ account-budgets/
    workspace-bootstrap/ instance-profiles/ unity-catalog-metastore/
    storage-credentials/ external-locations/ catalogs/ cluster-policies/ sql-warehouses/ job/
    data-access/
```

`infra/examples/vpc` is an example composition of the AWS modules. Reusable
modules must not contain environment-specific provider configuration, backend
configuration, credentials, or hard-coded account IDs.

## Module order and boundaries

The execution-order refactor is now implemented after the user retired the
current deployment and all four old states were verified empty. New deployments
use 01-infra → 02-account → 03-data-access → 04-workspace for object creation.
Dev/demo adds the independent 02-workspace-access feature state after 02-account
and before dataset access, without changing legacy 03/04 ownership. Root 03 owns
metastore setup and all UC objects; root 04 reads its state before compute setup.
The renamed roots use new backend keys. Old empty state keys are retained.
Initialize renamed roots with `terraform init -reconfigure -backend-config=backend.hcl`.
Do not use -migrate-state for this retired deployment or reuse saved old plans.
Other environments with live old states need an explicitly reviewed ownership
migration before adopting this layout. Code reorganization does not migrate state.

Apply whole roots rather than individual targeted modules. Keep root names,
backend keys, remote-state references, numbering, tests, and docs consistent.

Phase one — 01-infra:

1. vpc
2. subnets
3. egress
4. security-groups
5. vpc-endpoints
6. IAM-roles
7. optional kms
8. root-storage
9. optional kinesis
10. observability
11. data-storage

Phase two — 02-account:

12. account-configuration
13. workspace
14. optional account-groups
15. account-budgets

Phase three — 03-data-access:

16. unity-catalog-metastore or existing assignment
17. storage-credentials referencing deterministic planned role ARNs
18. uc-storage-roles using credential-generated trust
19. external-locations after IAM propagation
20. optional catalogs, schemas, and volumes

Phase four — 04-workspace:

21. workspace-bootstrap
22. instance-profiles
23. cluster-policies
24. sql-warehouses
25. job

26. Planned: Databricks PrivateLink; no runnable module yet.

Buckets stay in infra state. UC roles, credentials, external locations and new
catalogs share the separate data-access state to resolve generated external IDs
without reverse remote-state reads, manual copying, or bootstrap flags.
The data-access root uses AWS plus account and workspace Databricks providers.
Optional generic catalogs/locations are also owned by 03-data-access; never
duplicate the same object in its generic maps and data_access composition.
Use account groups from 02 for UC grants; do not depend on local groups from 04.
Read only necessary outputs from upstream states. Never place account-level
workspace creation and workspace-level configuration in the same state.

## Provider aliases

- Account-level Databricks resources use `databricks.accounts` and
  `https://accounts.cloud.databricks.com`.
- Workspace-level resources use `databricks.workspace` and the `workspace_url`
  output of the workspace module.
- Every reusable Databricks module declares its required alias with
  `configuration_aliases`; configure the provider only in the calling root.

Never combine account-level workspace creation with workspace-level resource
management in the same Terraform state.

## Terraform conventions

- Target Terraform `>= 1.7.0, < 2.0.0`.
- Pin provider major versions with a compatible constraint. Existing modules
  use Databricks provider `>= 1.100.0, < 2.0.0`.
- Each module contains `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`,
  `README.md`, and at least one mocked test under `tests/`.
- Give every variable a description, concrete type, `nullable` setting, and
  validation where format or safety is important.
- Give every output a description. Output IDs and ARNs that later modules need;
  do not output credentials or secrets.
- Use `for_each` with stable map keys for collections. Avoid `count` when
  instance identity needs to survive list reordering.
- Default to least privilege: no broad access grants, no cluster-creation or
  SQL entitlement unless explicitly requested, and no bypass of AWS validation
  unless justified.
- Keep KMS disabled unless an environment explicitly enables it.
- Do not make destructive changes, change remote state, or apply Terraform
  without explicit user authorization.

## Networking conventions

- Workspace subnets span at least two Availability Zones.
- The AWS S3, STS, and Kinesis endpoints are AWS service endpoints. Do not
  register them as Databricks PrivateLink endpoints.
- Databricks PrivateLink requires distinct endpoints to Databricks-managed
  endpoint services, registration in the Databricks account, and possibly
  private access settings. Keep this in its own optional module.

## Identity and data governance

- Optional init-script storage: data-access enable_init_scripts_volume adds the
  init_scripts managed volume/grants only. init_script_readers gets READ_VOLUME;
  grant parent usage separately. Do not store scripts in developer-writable logs.
- The hello-world source and databricks_file upload belong to cluster-policies,
  enabled by enable_hello_world_init_script in 04-workspace. Policy creation
  depends on upload. Historical live deployments need an explicit file ownership
  migration; a removed block alone does not import the file into another state.
  Never manage the file in both states. The retired deployment requires no import.
- cluster-policies init_script_volume_path fixes index-zero volumes.destination
  in direct/family policies. Default null, enabled in local dev. Apply 03 before
  04; create storage first. Standard compute needs an allowlist; serverless unsupported.
  No live compute is started for this demo. Remove compute/policy references
  before disabling the uploaded script.

- Optional dedicated operations storage uses data-storage enable_observability_bucket
  and observability_bucket_name. Preserve existing landing/uc_managed addresses.
  Output key observability flows to the same data-access state for a dedicated
  IAM role, credential, external location, and managed operations catalog/volume.
- data-access observability is an optional names/grants object, default null.
  Dev enables dev_operations.observability.cluster_logs. Readers receive no log
  grants; developers need volume read/write and parent usage for delivery.
- cluster-policies cluster_log_volume_path is optional/null by default and
  enforces fixed VOLUMES type/path for direct policies and policy families.
  Activation order: 01 → 02 → 03 → 04. Volumes and metastore setup are complete
  before compute configuration. Do not introduce a reverse remote-state dependency
  or create running compute to test logging.
  Log delivery is distinct from audit logs and CloudWatch infrastructure metrics.

- Development access packages are account groups: databricks-dev-admins (ADMIN),
  databricks-dev-developer (USER), databricks-dev-reader (USER). Preserve existing
  admin memberships. Developer/reader members are delegated with empty member_ids.
  account-groups optionally grants roles/group.manager via manager_group_names
  referencing other declared groups; requires databricks_account_id. Rule sets
  are authoritative. Delegate IdP membership at the IdP instead.
- 03-data-access exposes catalog_grants, schema_grants, incoming_volume_grants.
  Keep readers' SELECT scoped to gold; developers write medallion schemas and
  incoming; admins receive ALL_PRIVILEGES plus MANAGE. No grant transfers ownership.
  Maps are authoritative per securable; do not mix manual and Terraform grants.
  Workspace ADMIN, group manager, and Unity Catalog management are separate roles.
  Compute policy/warehouse permissions remain in 04-workspace; do not provision
  running compute just to provide group access.

- Prefer account-level users, groups, and service principals with identity
  federation for production. `workspace-bootstrap` only creates explicitly
  requested workspace-local identities.
- Use OAuth machine-to-machine authentication or workload identity federation
  for Terraform. Do not use or commit long-lived personal access tokens.
- Prefer Unity Catalog storage credentials and external locations for new data
  access. Instance profiles are for compute-level AWS access and legacy
  workloads that require them.
- `unity-catalog-metastore` assigns one metastore to one workspace. It defaults
  to no metastore-level storage root so later catalog modules can use isolated
  managed locations. A shared root requires an existing storage credential and
  its S3 path together.
- Unity Catalog S3 roles require the IAM principal and external ID returned by
  Databricks when the storage credential is created. Keep that trust-policy
  dependency in the dedicated data-access integration state.
- `external-locations` registers S3 paths with existing Unity Catalog storage
  credentials. Its grants map is authoritative for each managed location;
  do not manage grants for the same location in multiple resources.
- `catalogs` creates catalogs, schemas, and volumes. Its grants maps are
  authoritative at their respective securable level. `EXTERNAL` volumes require
  an S3 storage location; `MANAGED` volumes must not define one.
- `cluster-policies` creates policies from an HCL definition or a Databricks
  policy family, never both. Its permission maps are authoritative for each
  managed policy. Document CAN_USE as the explicit policy grant; workspace
  admins manage policies. Compute cluster ACLs are a separate concern.
- `sql-warehouses` uses bounded cluster counts and automatic shutdown. Its
  permission maps are authoritative for each managed warehouse; Unity Catalog
  grants remain the mechanism for governing data access.
- `job` manages notebook-based jobs. Tasks must use exactly one existing
  cluster or declared ephemeral job cluster; prefer the latter with a cluster
  policy. Job permissions do not replace Unity Catalog data grants.

## Required checks

Run `terraform fmt -check -recursive .` and `tflint --recursive` from the
repository root. Staging and production scaffolds must remain valid HCL even
before their module wiring is implemented. S3-lockfile roots require Terraform
>= 1.10.

After changing a module, run from that module directory:

```bash
terraform fmt -recursive .
terraform init -backend=false
terraform test
terraform fmt -check -recursive .
git diff --check
```

Do not commit `.terraform/`, `.tfstate`, `.tfvars` containing secrets, or
provider credentials. Commit `.terraform.lock.hcl` for each independently
initialized Terraform root or module when the repository convention adopts it.

## Environment roots

- Keep root README.md and AGENTS.md updated with every module or environment
  addition, as requested by the user.
- Development has four runnable phase roots in `environments/dev`. Keep
  distinct S3 keys for infra, account/workspace creation, and workspace setup.
- Environment roots require Terraform >= 1.10 for `use_lockfile` S3 locking.
- Pass AWS outputs through phase-one remote state and workspace URL/ID through
  phase-two remote state; never hard-code created IDs in downstream roots.
- Phase three uses the account alias for UC metastore setup alongside the
  workspace alias and AWS provider. Phase four uses the workspace alias only.
  Workspace creation stays in phase two.
- Module/root variable collection defaults are empty; metastore creation and
  instance-profile registration are explicitly opt-in. Local development
  `04-workspace/terraform.tfvars` enables `dev-single-node-basic`; distinguish
  configured tfvars from variable defaults. The policy creates no running
  cluster: one `m5d.xlarge` driver, zero workers, 20-minute idle termination,
  one active cluster per user, and CAN_USE for `databricks-dev-admins`.
  Reuse regional metastores when present.
- Do not claim production is runnable while it remains a scaffold.

- Instance-profile group assignments accept `group_ids_by_name` for computed
  group IDs with stable Terraform keys; use this when bootstrap creates groups
  in the same workspace state.

- `account-groups` creates account groups and memberships using existing numeric
  account SCIM IDs, then assigns USER or ADMIN access to one workspace. Wire it
  into phase two using `databricks.accounts`; defaults create no identities.
  Workspace ADMIN does not grant account admin. Do not duplicate ownership of
  memberships or workspace assignments, or manage IdP group membership here.

- `account-budgets` manages monthly Databricks email budget alerts using
  `databricks.accounts`. Defaults to 10 USD and 50/80/100 percent thresholds.
  Phase two enables its workspace budget when recipients are supplied. These
  are list-price alerts, not hard spending caps or AWS infrastructure budgets.

- `observability` creates AWS CloudWatch dashboards and NAT error alarms in
  phase one. EC2 discovery is restricted to the VPC and Vendor=Databricks;
  apply refreshes ephemeral instance membership. S3 request metrics are opt-in.
  SNS topics and subscriptions remain externally managed. CloudWatch metrics
  do not represent billing costs; use CUR/Cost Explorer for AWS spend.

## Teardown

Destroy whole roots in reverse order: 04-workspace → 03-data-access → 02-account
→ 01-infra. Keep metastore assignment/access until UC data objects are removed.
A reused regional metastore is not owned or deleted here. Resolve UC asynchronous
managed-data cleanup before forcing deletion of external locations. Versioned S3
buckets require deleting all versions and delete markers intentionally; keep
force_destroy=false defaults. Preserve the Terraform state bucket and history.
