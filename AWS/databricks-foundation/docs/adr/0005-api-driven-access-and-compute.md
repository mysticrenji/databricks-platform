# ADR 0005: YAML-driven access and compute through Python APIs

- Date: 2026-10-16
- Status: Superseded by [ADR 0006](0006-yaml-terraform-permissions.md) for deployment ownership and CI; retained as historical design
- Scope: Databricks AWS foundation, initially `dev/demo`
- Supersedes: [ADR 0001](0001-configuration-driven-access-management.md) for the access implementation approach
- Complements: [ADR 0004](0004-environment-workspace-isolation.md) for environment/workspace identity
- Implementation checklist: [Access and compute action items](../plans/api-access-and-compute-action-items.md)

## Context and decision

The user subsequently chose Terraform-managed groups and permissions on existing
data objects, with Python limited to validation/rendering/read-only checks. ADR
0006 is authoritative. The Python write/inventory/apply design below is historical.

Terraform remains responsible for building the platform. A small Python tool,
using the official Databricks SDK, will configure access and compute from YAML.
The platform team defines available personas, permission packages and compute
policies. Data teams submit access declarations through pull requests. Approved
declarations describe continuing desired access, rather than one-time API calls.

Use one repository. Separate platform-owned configuration from team-authored
access declarations with enforced review rules. Start with `dev/demo`; support
additional development workspaces through the same contract. Staging execution
is a later explicit rollout. Production remains configuration-only and must be
rejected by mutating commands and CI until separately authorized and implemented.

The first [dev/demo example](../../tools/databricks-access/README.md) implements
the YAML contract, credential-free validation and offline desired-state preview.
It has no SDK/live planner, apply command, ownership transfer or deployment
workflow. The remaining interface below is the implementation target, not a claim
of available commands. Existing Terraform behavior is unchanged until adoption.

## Responsibility and ownership boundaries

| Area | Intended owner after adoption |
| --- | --- |
| AWS VPC, buckets, KMS, deployment/storage IAM roles | Terraform roots 01 and 03 |
| Databricks account registrations, workspace, budgets | Terraform root 02 |
| Regional metastore/assignment, storage credentials and external locations | Terraform root 03 |
| Catalogs, schemas, volumes, their configured owners and workspace bindings | Terraform root 03 |
| Account groups created for this feature, workspace USER/ADMIN assignments, supported group entitlements | Python |
| Persona definitions, permission packages, compute specifications | Platform-owned YAML, interpreted by Python |
| Direct UC grants for registered group/object scopes | Python |
| Classic compute policies, SQL warehouses and their group ACLs | Python |
| Users and group membership | Identity provider or separately delegated identity administrators |
| Tables/views and their lifecycle | Application/dbt/data pipelines |
| Jobs, instance profiles, init-script files and unrelated existing resources | Existing Terraform/application owner; outside this delivery |

A persona is our configuration profile, not a new native Databricks role or an
AWS IAM role. People join account-level groups. Unity Catalog's platform storage
roles provide S3 access behind the scenes; a reader/writer package does not give
people AWS credentials, storage-credential use or direct S3 permissions.

Workspace ADMIN, account admin, group manager, catalog ownership and UC MANAGE
are separate powers. No package below grants ownership, MANAGE, ALL_PRIVILEGES,
account admin or group management. Catalog ownership remains explicit in Terraform.
The platform administrator group may be selected there as owner after the group
exists; do not derive ownership from an access request.

No resource, ACL or membership can be managed by both Terraform and Python.
Unadopted Terraform deployments keep their existing behavior. Preserve reusable
modules; do not delete them simply because the new path uses APIs.

## Configuration layout and review ownership

Paths are relative to `AWS/databricks-foundation/`:

```text
platform/                                # Administrator-owned inputs
  environments/dev/demo.yaml              # Existing provisioning configuration
  access/
    roles.yaml                            # Personas and exact privilege packages
    reviewers.yaml                        # Trusted platform/data-owner reviewer mapping
    targets/dev/demo.yaml                 # Trusted account/workspace/metastore identities
    principals/dev/demo.yaml              # Group registry and persona assignments
    resources/dev/demo.yaml               # Approved existing data objects and their owners
  compute/
    dev.yaml                              # Shared dev compute definitions
    staging.yaml                          # Future, no execution in initial rollout
    production.yaml                       # Future, configuration-only
  terraform-inputs/                       # Optional JSON inputs, no code/state
    dev/demo.01-infra.json
    dev/demo.02-account.json
workloads/                                # Under databricks-foundation, outside platform
  data-engineering/dev-demo.yaml           # Requested persona and data access only
  data-analytics/dev-demo.yaml
  data-science/dev-demo.yaml
```

Compute access is entirely platform-managed through personas. Workload authors
request an approved persona and data access; they cannot choose cluster policies,
warehouses or capabilities. Platform configuration binds each workload to its
group/persona. Capability requests are deferred to a later contract extension.

The platform folders replace the former generic config tree. Terraform execution
roots stay in `environments/`; this is a file-layout change, not a state or cloud
ownership migration. Existing GitHub ENVIRONMENT_CONFIG_PATH variables must be
updated before running workflows; see [platform operations](../../platform/README.md).

Platform approval is required for all `platform/**` inputs,
Python code, dependency locks, workflow files and CODEOWNERS. Data owners approve
requests for the datasets they own. The initial rollout additionally requires
platform approval for every access change. The target/resource registries and
reviewer mappings are platform-controlled; request authors cannot nominate their
own approver, arbitrary workspace endpoint, principal or dataset owner.

GitHub CODEOWNERS routes reviews but cannot alone enforce approval from both a
platform reviewer and a data owner. Require branch protection/rulesets and a
trusted approval check that verifies both categories against platform-owned
mappings, excludes the author, and invalidates approval after relevant changes.
Protect those mappings and the check itself. If this cannot be enforced on the
repository's GitHub plan, keep apply manual behind a platform environment gate
and document the limitation; do not claim a two-party gate exists.

## YAML contract

Every document has `version: 1`. Decode strictly: reject duplicate keys, aliases,
unknown fields, invalid types, wildcards and unresolved logical references.
Use JSON Schema plus small Python semantic checks; no YAML templating, embedded
code, arbitrary SQL, dynamic imports or arbitrary raw API payloads.

The following examples define the intended contract, not executable configuration.

### Platform-owned packages and personas

`platform/access/roles.yaml`:

```yaml
version: 1
packages:
  reader:
    catalog: [USE_CATALOG]
    schema: [USE_SCHEMA, SELECT]
    table: [SELECT]
  writer:
    schema: [USE_SCHEMA, SELECT, MODIFY, CREATE_TABLE]
    table: [SELECT, MODIFY]
personas:
  admins:
    workspace_role: ADMIN
    allowed_packages: []
    cluster_policies: []
    sql_warehouses: {analytics: CAN_MANAGE}
    entitlements: {workspace_access: true, databricks_sql_access: true}
  engineers:
    workspace_role: USER
    allowed_packages: [reader, writer]
    cluster_policies: [engineering-standard]
    sql_warehouses: {analytics: CAN_USE}
    entitlements:
      workspace_access: true
      databricks_sql_access: true
      allow_cluster_create: false
      allow_instance_pool_create: false
  analysts:
    workspace_role: USER
    allowed_packages: [reader]
    cluster_policies: []
    sql_warehouses: {analytics: CAN_USE}
    entitlements:
      workspace_access: true
      databricks_sql_access: true
      allow_cluster_create: false
      allow_instance_pool_create: false
  ml:
    workspace_role: USER
    allowed_packages: [reader, writer]
    cluster_policies: [ml-standard]
    sql_warehouses: {analytics: CAN_USE}
    entitlements:
      workspace_access: true
      databricks_sql_access: true
      allow_cluster_create: false
      allow_instance_pool_create: false
```

Omitted package/object combinations are invalid: writer-on-catalog is not allowed.
Table SELECT/MODIFY expansion also adds USE_CATALOG and USE_SCHEMA on its parents;
schema expansion adds USE_CATALOG. Catalog reader grants usage only, not blanket
SELECT. Derive parent usage centrally and retain it while any request needs it.

Non-admin cluster policy ACLs use CAN_USE. Workspace admins manage policies via
their administrative rights; do not invent a policy CAN_MANAGE grant. Warehouse
ACLs explicitly use CAN_USE or CAN_MANAGE. `allow_cluster_create: false` restricts
unrestricted cluster creation; approved policy use remains a separate permission.
Report wider effective entitlements from other groups rather than claiming a
false flag overrides them. Admins are privileged and are not confined by the
ordinary persona limits.

Membership in the engineer persona permits requesting writer access; it does
not automatically grant data access. ML model registry, serving, experiments,
feature engineering and job permissions are not implied by the ML persona.

### Trusted target, principal and resource registries

`platform/access/targets/dev/demo.yaml` must bind environment/workspace to the
expected Databricks account ID, workspace ID, workspace URL and metastore ID.
Populate it through reviewed provisioning outputs; verify those identities live
before planning. Environment identity must also match `platform/environments`.
Do not read an entire Terraform state just to discover the workspace URL.

Its required fields are `version`, `environment`, `workspace`, `account_id`,
`workspace_id` (numeric string), `workspace_url` (HTTPS workspace host),
`metastore_id` and `active` (boolean). Only active registered targets may be
selected; identity changes require platform review and a fresh inventory binding.
`platform/access/reviewers.yaml` contains `version`, `platform_reviewers` and
`data_owners`; each reviewer set lists GitHub logins or organization-team slugs.
Resolve team membership through trusted GitHub APIs; unknown/inaccessible teams
fail the approval check. Requests cannot supply substitute reviewer identities.

`platform/access/principals/dev/demo.yaml`:

```yaml
version: 1
environment: dev
workspace: demo
groups:
  admins: {display_name: dev-demo-admins, persona: admins, lifecycle: create}
  engineers: {display_name: dev-demo-engineers, persona: engineers, lifecycle: create}
  analysts: {display_name: dev-demo-analysts, persona: analysts, lifecycle: create}
  ml: {display_name: dev-demo-ml, persona: ml, lifecycle: create}
```

`lifecycle: create` permits creating a missing account group, then tracking its ID.
An existing matching name must not be silently adopted: require a reviewed import
with `lifecycle: external` and `account_group_id` (numeric string). External groups
are never deleted or have membership replaced. The registry's workspace assignment
is still managed by this tool after explicit adoption. Reject duplicate names/IDs
and more than one persona per group in this workspace in version 1.

Group IDs are account-scoped. Multiple workspace registries may reference the same
external group, but group lifecycle has exactly one central owner. Initial groups
are workspace-specific as illustrated. Membership is never declared in these files.
Automation service principals use a separate explicit registry extension later;
do not place them into human personas implicitly.

`platform/access/resources/dev/demo.yaml`:

```yaml
version: 1
environment: dev
workspace: demo
datasets:
  dev_demo:
    approval_owner: analytics-data-owners
    schemas:
      bronze: {allowed_packages: [reader, writer]}
      silver: {allowed_packages: [reader, writer]}
      gold: {allowed_packages: [reader]}
      ml: {allowed_packages: [reader, writer]}
workloads:
  data-engineering:
    principal: engineers
    allowed_catalogs: [dev_demo]
  data-analytics:
    principal: analysts
    allowed_catalogs: [dev_demo]
  data-science:
    principal: ml
    allowed_catalogs: [dev_demo]
```

The schema allowlist also bounds table packages beneath that schema. Gold is
read-only in this example; changing that is a platform/data-owner policy decision.
`approval_owner` refers to an approved GitHub reviewer mapping, not a Databricks
principal. Workload access files cannot change these limits. Data objects must already
exist. Version 1 supports simple lowercase SQL identifiers separated into explicit
catalog/schema/table fields; reject quoted/dotted component names rather than
guessing how to parse them. No cross-metastore names.

### Environment-level compute definitions

`platform/compute/dev.yaml`:

```yaml
version: 1
environment: dev
cluster_policies:
  engineering-standard:
    description: Bounded engineering compute
    runtime:
      allowed_versions: ["16.4.x-scala2.12"]
      default_version: "16.4.x-scala2.12"
    worker_nodes:
      allowed_types: [m5d.large, m5d.xlarge]
      default_type: m5d.large
    driver_nodes:
      allowed_types: [m5d.large]
      default_type: m5d.large
    autoscaling: {min_workers: 1, max_workers: 2}
    autotermination_minutes: 20
    max_clusters_per_user: 1
    data_security_mode: USER_ISOLATION
  ml-standard:
    description: Bounded CPU ML compute
    runtime:
      allowed_versions: ["16.4.x-cpu-ml-scala2.12"]
      default_version: "16.4.x-cpu-ml-scala2.12"
    worker_nodes:
      allowed_types: [r5d.large, r5d.xlarge]
      default_type: r5d.large
    driver_nodes:
      allowed_types: [r5d.large]
      default_type: r5d.large
    autoscaling: {min_workers: 1, max_workers: 2}
    autotermination_minutes: 20
    max_clusters_per_user: 1
    data_security_mode: SINGLE_USER
sql_warehouses:
  analytics:
    size: Small
    min_clusters: 1
    max_clusters: 1
    auto_stop_minutes: 15
    enable_serverless_compute: false
```

Runtime IDs and node types here are illustrative, not a guarantee of availability.
`spark_version` in the API means Databricks Runtime, which bundles Apache Spark;
do not offer an independently configurable Apache Spark version. Pin approved
runtime IDs in version 1 rather than floating latest aliases. Fetch supported
runtimes and node types from the target workspace when planning, including ML
runtime/access-mode compatibility. Supported node types do not guarantee AWS
capacity or quota. Reject unsupported combinations before writing anything.

Compile friendly fields into native policy constraints: runtime/node allowlists
and defaults; fixed access mode and idle termination; bounded autoscale min/max
with min <= max; forbid fixed `num_workers` to prevent bypassing autoscale limits.
Version 1 supports classic multi-node compute only, no pools, GPU, single-node,
custom images, arbitrary init scripts or alternative node-flexibility bypasses.
The compiler must close alternative paths for constrained settings; document the
exact native JSON and negative tests. Dedicated ML compute requires a supported
assigned-user configuration; no group-assigned dedicated compute in this version.

Definitions are shared per environment, but policy and warehouse objects are
created separately in each explicitly registered workspace. Resolve stable IDs
from the inventory, not first-match display-name searches. No workspace overrides
in version 1. An environment compute change must plan every registered active
workspace in that environment, with separate approvals/results; never silently
update just one and claim rollout complete. Unknown/inactive workspaces are not
deployment targets. Persona policy/warehouse references must resolve in every
target selected for rollout.

Policy creation starts no clusters. Warehouse creation can provision billable
compute: keep it behind explicit plan/apply review, do not start it for tests,
and display cost-relevant settings. Policy edits do not promise running clusters
have been restarted or brought into compliance. Existing-cluster remediation is
a separately approved operation.

### Workload-authored continuing access

`workloads/data-engineering/dev-demo.yaml` (relative to databricks-foundation):

```yaml
version: 1
environment: dev
workspace: demo
persona: engineers
data_access:
  - id: bronze-write
    catalog: dev_demo
    schema: bronze
    access: writer
    reason: Maintain bronze ingestion tables
  - id: sales-summary-read
    catalog: dev_demo
    schema: gold
    table: sales_summary
    access: reader
    reason: Validate published sales totals
```

The folder identifies the workload; it must be registered by the platform, which
resolves its `principal` to an account group. The requested persona must match
that group's approved persona. The filename is `<environment>-<workspace>.yaml`
and target fields must match it; this first slice accepts `dev-demo.yaml` only.
Validate persona packages, workload catalog limits and schema package limits;
a valid package alone is not authorization to a dataset. A catalog-only entry
requests usage; adding schema scopes to that schema; adding table requires schema
and scopes to that table. IDs are stable and unique within a workload/target.
Multiple workload files may contribute to the same grant;
union all contributions before calculating changes. Ordering must not affect output.
Workloads cannot supply groups, ownership, raw privileges, admin powers, membership,
compute definitions, policy/warehouse choices or capabilities. Persona selection
is a request constrained by platform mappings, not a way to self-promote.
Reject the superseded `config/access` layout rather than silently ignoring it.

Schema SELECT covers current and future tables/views. Table-level declarations
cannot subtract inherited access. Previews must identify broad ancestor grants,
ownership/admin powers and other group access discovered by the available APIs;
never describe removal of a direct grant as proof that all effective access ended.
Do not claim exhaustive effective-user analysis when group visibility is incomplete.
Table requests fail clearly if the object does not exist; application creation
must precede access deployment. Do not silently skip or create missing tables.

## Python implementation and reconciliation

Entry point: `tools/databricks-access/access.py`, with a README,
versioned schemas, pinned dependencies and focused unit tests in that folder.
Use the official `databricks-sdk` with `AccountClient` for account groups and
workspace assignments and `WorkspaceClient` for grants, policies and warehouses.
Keep validate/load, desired-state expansion, live reads/plan and apply in small
separate modules. No plugin framework, custom DSL or replacement Terraform engine.

The original proposed name `platform.py` shadows Python's standard-library module;
implementation uses `access.py`. Currently only `validate` and `preview` exist.
The live `plan` and `apply` interfaces below are future work. `preview` explicitly
emits a non-executable offline desired-state document, with no live comparison.

```bash
python3 tools/databricks-access/access.py validate --environment dev --workspace demo
python3 tools/databricks-access/access.py preview --environment dev --workspace demo
# Future commands, not yet implemented:
python3 tools/databricks-access/access.py plan --environment dev --workspace demo --out plan.json
python3 tools/databricks-access/access.py apply --plan plan.json
```

`validate` is credential-free. `plan` reads live state and writes a deterministic,
human-readable report plus a machine plan; it performs no provisioning or API
mutation. `apply` consumes a reviewed plan, not fresh arbitrary configuration.
The plan binds the commit, tool/dependency/schema versions, all contributing YAML
hashes, verified target IDs, inventory revision and observed resource/ACL hashes.
Hash all target files, not only files changed in the PR. Version 1 plans expire
after 24 hours; verify expiry before any write. Re-read affected state before
execution; changed bindings or live preconditions invalidate the plan and require
new planning and approval. Databricks APIs are not a multi-resource transaction;
document the remaining race with out-of-band administrators.

Use paginated reads and bounded retries/backoff for rate limits, transient errors
and identity propagation. Distinguish forbidden/missing/error from empty results.
After ambiguous create responses, reconcile by recorded operation identity and
unambiguous lookup before retrying; never create duplicates blindly. Validate all
references/preconditions before mutations, create groups before assignments,
create compute objects before ACLs, and add parent usage before child privileges.
For removals revoke obsolete child grants before unused parent usage. Verify
postconditions; stop on failure with the successful and pending operations listed.

### Inventory, deletion and drift

Python does not use Terraform state, but it needs a small durable ownership
inventory. Store versioned JSON in a protected, versioned S3 bucket under
`databricks-access/<account-id>/inventory.json`, separate from `.tfstate` keys.
The existing state bucket may host it with separate prefix permissions. Include
resource IDs, target/metastore identities, managed direct grant tuples, source
request IDs, before/after snapshots and operation progress. No tokens or secrets.
Use conditional writes on inventory revisions and an account-scoped deployment
lock; refuse apply when storage/locking is unavailable. Do not rely on ephemeral
GitHub artifacts as the sole ownership record. Version 1 serializes all access
applies in the account, including different workspaces sharing a metastore.

Configure storage through `DATABRICKS_ACCESS_INVENTORY_BUCKET` and
`DATABRICKS_ACCESS_INVENTORY_REGION`, outside workload YAML. The lock key is
`databricks-access/<account-id>/apply.lock`: conditionally create it only when
absent, record a unique owner/run ID, and release only that owner's lock. Do not
steal a lock on a timer; after a crashed run, an operator verifies the run stopped
and resolves its journal before explicitly clearing the lock. Use revision/ETag
preconditions for inventory updates. Test these storage operations with fake S3.

UC grants belong to a metastore, not an individual workspace. Key them by
metastore ID, securable type/full name and principal ID. Union contributions from
all registered targets in that metastore before revocation. Per-workspace files
describe the requesting context, not separate UC ACLs. Preserve shared grants
while another active request needs them. Terraform must configure appropriate
catalog isolation/workspace bindings; a workspace YAML label alone is no boundary.

On adoption, explicitly register owned direct grant scopes and object IDs after
reviewing a read-only baseline. An existing name or grant is not proof of ownership.
For adopted group/object pairs, reconcile the exact approved direct privileges;
unexpected direct privileges are drift and must appear as reviewed removals, not
be silently preserved. UC changes use explicit add/remove deltas, never wholesale
replacement of unrelated principals. Other principals' grants are read-only;
unexpected broad access is reported for its actual owner to resolve. Ownership,
inherited grants and administrative rights are not ordinary direct grants.

Removing a request revokes only managed privileges no longer required by any
approved declaration. Empty `data_access` means no desired data grants for that workload, not
revoke every permission on the object. Removing a workload file is supported because
the inventory retains its previous contributions. Missing/empty inventory must
not trigger destructive reconciliation: require bootstrap/import review first.

Removing groups/policies/warehouses from YAML marks them pending retirement and
fails normal apply until resolved. Object deletion is a separate platform-only
retire operation requiring ID/target confirmation, dependency checks and a reviewed
plan. No automatic catalog/schema/table deletion, group-membership clearing,
ownership transfer or workspace-admin removal. Admin assignment changes require
a separate reviewed migration preserving the deployment identity and a recovery
administrator. Compute ACL replacement APIs can delete omitted permissions; only
use replacement for explicitly adopted ACL ownership with all preserved required
entries included. Exclude inherited/system entries from write payloads.

Before each mutation, persist its intent and before-image. On success record the
result; on partial failure retain the journal and rebuild a fresh plan from live
state. No automatic broad rollback. Recovery is an explicitly reviewed reverse
diff against live state; rerunning an old plan is not recovery. Reordering YAML
must produce no changes, and a second plan after successful apply must be empty.

## CI and authentication

1. PR CI runs offline validation/unit tests without deployment credentials.
   Untrusted PR code never runs with account/workspace credentials; do not use
   `pull_request_target` to execute a contributor's scripts with secrets.
2. Trusted platform code may produce a read-only PR preview treating proposed YAML
   strictly as data. Protect the planner implementation, redact sensitive identity
   details and label preview limitations. Offline checks alone are not a live plan.
3. After required reviews and merge to protected main, trusted CI plans again for
   the exact merged commit. Show additions, revocations, inheritance warnings,
   admin changes, affected workspace IDs and compute settings. No automatic apply
   just because a PR merged.
4. A protected `<environment>-<workspace>-apply` GitHub Environment gates each
   mutating target. Require platform approval with self-review disabled, restrict
   deployment branches and require an explicit access-apply opt-in variable
   `DATABRICKS_ACCESS_APPLY_ENABLED=true` (separate from Terraform apply/destroy).
   Approval applies to the immutable plan artifact for this run; changing the plan
   requires another approval. Do not accept uploaded arbitrary plan paths/URLs.
5. Apply the bound plan, verify results and save inventory/journal and a run summary.
   No credentials, API tokens or full Terraform states in artifacts/logs. Restrict
   plan/journal access; retain run artifacts for 7 days and durable inventory history
   for 90 days initially, subject to the platform's retention requirements.

Use OAuth service principals via Databricks unified authentication; prefer workload
identity federation when configured. Otherwise use securely stored M2M client
credentials. Existing GitHub AWS OIDC is not itself Databricks authentication.
Use account credentials only in group/assignment operations; use a workspace
deployment identity authorized for managed UC scopes and compute for the rest.
Verify required privileges and do not assume workspace admin grants all UC rights.
The baseline read-only planner has no write role. Restrict AWS inventory access
separately from infrastructure provisioning. No personal access tokens in YAML.

Keep provision, access and deprovision runs from racing. Reuse the existing
`databricks-environment-<environment>-<workspace>` concurrency group for per-target
operations, do not cancel an in-progress mutation, and acquire the shared account
inventory lock for access operations. The account lock must cover shared UC grants
even when GitHub jobs target different workspaces. Add a read-only scheduled drift
plan later; do not auto-correct permissions without review.

The environment setup helper must eventually configure the access opt-in and
document any additional identity/inventory variables. It must retain dry-run mode,
never silently enable apply and never claim to configure reviewers/branch rules
it did not actually configure. Initial workflow execution is dev-only; preserve
the existing staging provisioning behavior and production block.

## Adoption, teardown and recovery boundaries

First inventory configured and live ownership in roots 02/03/04. Existing optional
group, grants, policy and warehouse maps can all conflict with Python. Choose one
owner for each resource and whole ACL scope; reject raw Terraform declarations
for Python-adopted scopes, including supplemental `platform/terraform-inputs` inputs.
Disabling an empty-map grant resource is not evidence that privileges were revoked.
Terraform's authoritative `databricks_grants` resource covers a whole securable:
do not leave it managing other principals on the same object after Python adopts
some principal grants there. Transfer that whole Terraform grant-resource scope;
baseline and preserve unrelated entries under the declared ownership rules.

For live resources, prepare a reviewed transfer that removes Terraform ownership
without destroying the object (for example an explicit removed block with
`destroy = false`), imports the API identity/baseline into the inventory, and proves
Terraform will not recreate it. Never remove configuration and run an ordinary
apply if that would destroy the resource. Do not transfer remotely or change state
as part of documentation/testing. Root 03 continues owning objects, their owners,
bindings and storage integration; separate its grant resources before adoption.

Fresh deployment ordering: Terraform 01/02 creates infrastructure/workspace;
Python registers groups and workspace assignments; Terraform 03 establishes
storage/catalog/schema objects and explicit group ownership/bindings; Python
applies data grants and compute. Terraform 04 runs only for separately owned
resources with overlapping compute/identity/ACL maps disabled. Exchange minimal
reviewed outputs, not a reverse Terraform remote-state dependency. Root 03/04
are not currently wired into the environment adapter: namespace/naming fixes,
target identity checks and explicit orchestration are prerequisites to claiming
an end-to-end pipeline. Account group creation must not depend on catalogs.

Before workspace deprovisioning, retire its API-managed compute/assignments and
remove its grant contributions while preserving other targets' access. Leave
external groups and centrally shared resources intact. Extend ADR 0003's preview
and blockers to inspect API inventory; empty Terraform 03/04 states alone no
longer prove that downstream resources are absent. Fail closed if inventory or
target discovery is unavailable. Preserve the existing S3/KMS retention behavior.
Do not enable the access apply workflow until this teardown guard exists.

## Alternatives and consequences

- Terraform-only access remains valid for unadopted deployments, but was not chosen
  for the new team workflow because the user prefers Python/API management.
- Add-only API scripts are simpler but leave obsolete access behind; rejected.
- A separate repository per concern adds coordination and approval complexity;
  defer until ownership/scale requires it.
- Workspace-specific copies of compute specifications duplicate policy intent;
  share environment definitions and deploy separate workspace instances instead.

This approach gives teams a small access declaration and keeps platform control
centralized. It also makes our tool responsible for comparison, revocation,
inventory, concurrency and partial-failure recovery. Keep that scope explicit and
implement it in small phases rather than hiding those duties behind API calls.

## Implementation acceptance criteria

- Strict offline schema/semantic checks, complete example fixtures and useful errors.
- Exact package expansion and authorization at persona, workload and resource scope.
- Account IDs/principals/targets resolved without silent name adoption or skipped errors.
- Runtime/node/access-mode checks and native compute policy constraints tested.
- Union across files/workspaces, parent usage reference tracking and removal coverage.
- Drift, stale plans, concurrent applies, missing inventory and partial failure tests.
- No Terraform/Python overlap; reviewed adoption evidence and teardown inventory guard.
- Enforced trusted CI/review boundaries; dev-only rollout; no cloud writes in tests.
- Idempotent second plan, deterministic diffs and secret-free logs/artifacts.

## References

- [Databricks Python SDK](https://docs.databricks.com/aws/en/dev-tools/sdk-python): official account/workspace clients and authentication.
- [UC privileges](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/privileges-reference): parent usage and schema inheritance.
- [SDK grants API](https://databricks-sdk-py.readthedocs.io/en/latest/workspace/catalog/grants.html): direct/effective reads, pagination and explicit grant changes.
- [Compute policy reference](https://docs.databricks.com/aws/en/admin/clusters/policy-definition): native runtime/node constraints.
- [Object permission replacement API](https://docs.databricks.com/api/access-management/v1/set-object-permissions): replacement ACL semantics.
- [Workspace/catalog bindings](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/workspace-catalog-binding): workspace isolation is separate from grants.
- [GitHub CODEOWNERS](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners): review routing and enforcement limits.

Recheck SDK/API support against pinned versions during implementation. This ADR
authorizes documentation only, not live applies, ownership transfers or teardown.
