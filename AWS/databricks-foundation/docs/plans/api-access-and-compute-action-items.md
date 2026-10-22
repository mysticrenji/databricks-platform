# API access and compute: implementation handoff

> Historical backlog: superseded by [ADR 0006](../adr/0006-yaml-terraform-permissions.md).
> Do not implement the Python write engine/inventory below. The active flow is
> `terraform_permissions.py` and the dedicated Terraform permissions root.

Date: 2026-10-16. Status: First dev/demo offline slice implemented; no live API deployment.

Authoritative design: [ADR 0005](../adr/0005-api-driven-access-and-compute.md).
Read it and AGENTS.md before coding. The old ADR 0001 Terraform-adapter backlog
is historical. Initial target is `dev/demo`; do not rename it to primary.

## P01 — Inventory and ownership boundary

- [x] Inspect roots 02/03/04 and their modules, tfvars and supplemental JSON (repository only).
- [x] Record configured resource/ACL owners, stable ID outputs and default behavior in `tools/databricks-access/OWNERSHIP.md`; live IDs remain unverified.
- [x] Identify overlapping group, workspace assignment, grants, compute and warehouse inputs.
- [ ] Define the API-adoption switch/registry and reject competing Terraform inputs.
- [ ] Separate object lifecycle/ownership/bindings from grants in root 03 without changing legacy callers.
- [ ] Specify target identity exports and root 03/04 environment/workspace naming fixes.
- [ ] Write fresh-deployment and live-adoption runbooks; do not mutate remote state.

Done when: every resource/whole Terraform ACL has one intended owner, including
existing init scripts/log volumes, with no implied automatic migration.

## P02 — Strict contract, examples and offline validation

Offline work can proceed from the documented P01 repository snapshot; P01 live
ownership/adoption tasks still block live API rollout.

- [x] Add `tools/databricks-access/` with README, pinned dependencies and schemas.
- [x] Add the ADR's roles, principals, resources, reviewers, inactive target and compute fixtures.
- [x] Add dev/demo engineer, analyst and ML examples under foundation-local `workloads/`, with parent usage expansion and platform-approved persona/group bindings.
- [x] Validate package/object combinations, workload/resource limits and logical identities.
- [x] Reject aliases/duplicates/unknown fields, wildcard principals and forbidden powers.
- [x] Validate path/target identity; no mutating commands exist and non-demo targets fail.
- [x] Test exact expansion, stable IDs, deduplication and order independence.

Done when: `validate` works without credentials and all examples and negative
fixtures have tests. No API writes or Terraform changes required to validate.

## P03 — SDK reads and deterministic planning

Depends on P02.

- [ ] Implement account/workspace client adapters and target identity preflight.
- [ ] Read direct/effective grants, groups/assignments/entitlements, policies and warehouses.
- [ ] Handle pagination, 403/404, throttling and transient errors without false empty results.
- [ ] Check runtime IDs, node types, ML/access-mode compatibility and policy constraints.
- [ ] Compile and display native policy JSON with no autoscale/pool/flexibility bypasses.
- [ ] Generate immutable bound plans with observed hashes and 24-hour expiry.
- [ ] Discover all targets affected by environment compute edits; report each independently.
- [ ] Test table-not-yet-created, ambiguous names, unsupported configuration and drift cases.

Done when: plan is read-only, deterministic and identifies additions, revocations,
inheritance limitations, cost-relevant settings and all affected targets.

## P04 — Durable inventory and bounded reconciliation

Depends on P03.

- [ ] Implement versioned S3 inventory, revision checks and an account-level lock.
- [ ] Add reviewed bootstrap/import; never infer ownership from matching names.
- [ ] Track grants by metastore/object/principal and union every active request contribution.
- [ ] Reconcile only adopted direct privilege scopes, preserving unrelated/system/inherited ACLs.
- [ ] Add parent-first creation and child-first revocation with reference tracking.
- [ ] Journal intent before mutation; validate stale-plan preconditions and verify results.
- [ ] Test lock conflicts, lost inventory, interrupted create, partial apply and retry recovery.
- [ ] Keep group/policy/warehouse deletion and admin removal outside normal apply.

Done when: mocked SDK/S3 tests prove exact revocations, shared-target preservation,
no duplicate creation, recoverable partial failure and an empty second plan.

## P05 — Adoption and teardown protection

Depends on P04; required before enabling mutating CI.

- [ ] Implement local configuration overlap checks and document reviewed Terraform release/import.
- [ ] Preserve externally managed membership, admin access and regional shared resources.
- [ ] Document provisioning order and minimal output exchange; avoid reverse remote-state reads.
- [ ] Extend deprovision preview/blockers to inspect API inventory even when TF roots are empty.
- [ ] Block deprovision if inventory is unreadable or active API resources/contributions remain.
- [ ] Add a separately gated retirement plan for API resources and workspace contributions.
- [ ] Preserve ADR 0003's S3/KMS retention, confirmation and upstream/downstream safeguards.

Done when: neither provision nor destroy can silently bypass the new ownership layer.
Live migration, applies and destroys remain separately authorized operator actions.

## P06 — Trusted CI and development rollout

Depends on P05.

- [ ] Add credential-free PR validation and trusted read-only previews where configured.
- [ ] Add post-merge plan, protected environment approval and apply of that exact plan.
- [ ] Enforce both platform and dataset-owner approvals; protect trusted reviewer mappings/code.
- [ ] Reject untrusted code execution with credentials and mutable/arbitrary plan artifacts.
- [ ] Use per-target provision/access/destroy concurrency plus the shared account lock.
- [ ] Configure separate planning/write identities with required account/UC/compute permissions.
- [ ] Extend the GitHub setup helper for `DATABRICKS_ACCESS_APPLY_ENABLED`, default false.
- [ ] Document authentication, inventory storage/retention, approvals and limitations in READMEs.
- [ ] Add workflow lint and mocked end-to-end dev/demo tests; no running compute in tests.

Done when: the feature is ready for an explicitly approved dev/demo pilot, not
automatically deployed. Staging access and production mutation remain blocked.

## First-slice evidence (2026-10-16)

Branch: `feat/demo-access-yaml`. Implemented `access.py validate` and `preview`,
not live plan/apply. The validation workflow runs credential-free tests and offline
previews only; P06's trusted live preview/approval work is still pending. Target
IDs/reviewer mappings are deliberately inactive placeholders. No SDK installed,
cloud calls, remote-state changes or identity/ACL adoption performed. Added empty
demo supplemental JSON alongside the renamed demo provisioning YAML; legacy
primary files remain untouched. See the tool README for runnable commands.

Verification: 29 new Python authorization/expansion/compute and subprocess CLI
tests, plus 41 existing environment-runner tests passed. Workflow actionlint,
repository Terraform fmt, foundation TFLint, 39 documentation links and whitespace
checks passed. Repository-wide TFLint reports nine existing warnings under
`AWS/poc` and local reference material outside this foundation; no Terraform source
was changed. Native policy preview is draft: workspace runtime/node support and
API acceptance remain P03 work.

Workload refactor: declarations now live at
`AWS/databricks-foundation/workloads/{data-engineering,data-analytics,data-science}/dev-demo.yaml`.
Files request only a persona and `data_access`; the platform registry selects the
group and personas select compute. Old `config/access` declarations are rejected.
CI watches the foundation workloads path. Before/after desired-state comparison
proved unchanged groups, direct grants, compute definitions and ACLs; provenance
now uses workload names. The temporary repository-root workloads folder was removed.

## Verification and handoff rules

Platform layout refactor (2026-10-16): administrator inputs now live under
`platform/{environments,compute,access,terraform-inputs}/`; consumer requests stay
in `workloads/`. Updated tools, workflow defaults/path filters, ignores, READMEs
and AGENTS.md. All 23 moved inputs retained identical contents and the complete
desired-access/compute preview matched the baseline. Checks passed: 29 access
tests, 42 environment tests (including helper default-path coverage), actionlint,
Terraform fmt, foundation TFLint, seven environment templates, 87 local Markdown
links and whitespace validation. See `platform/README.md` for existing GitHub
ENVIRONMENT_CONFIG_PATH updates; no cloud/state/GitHub settings were changed.

Use focused Python tests with fake SDK/S3 responses; prove negative authorization,
revocation, concurrency and recovery cases rather than mirroring implementation.
Validate example YAML and CLI help offline. Run actionlint for changed workflows.
If Terraform changes, also run repository fmt/TFLint and affected mocked module
tests per AGENTS.md. Update README.md, AGENTS.md and ADR status as phases complete.

Record changed files, commands/results and unresolved limitations after each
phase. Do not mark mocked permission expansion as proof of live effective access.
No production rollout, cloud writes, GitHub settings changes, state transfer or
reference-directory edits are authorized by this checklist. Defer masks, filters,
ABAC, serving, GPU, arbitrary user grants and workload provisioning to separate scope.
