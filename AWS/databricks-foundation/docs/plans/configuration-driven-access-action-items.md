# Configuration-driven access: future action items

Created: 2026-10-14

Status: Historical backlog; superseded on 2026-10-16.

> Implement [ADR 0005](../adr/0005-api-driven-access-and-compute.md) using the
> [API access and compute checklist](api-access-and-compute-action-items.md).
> The Terraform adapter sequence below is retained for reference only; it is not
> the current Codex handoff. Its privilege/ownership findings remain useful input.

Architecture: [ADR 0001](../adr/0001-configuration-driven-access-management.md).

## Objective and scope

Make infrastructure and Unity Catalog access declarations reviewable through
validated configuration above this foundation's existing Terraform modules.
Preserve current behavior for callers that do not opt in. The initial delivery
covers schema access packages and account-group references; infrastructure IAM,
compute personas, and table exceptions have separate follow-up items.

The external `work/DB` review is inspiration and evidence, not the implementation
target. Do not edit it as part of this backlog. Its private modules were not
available, and effective live privileges were not verified.

## Ordered backlog

### A01 — Inventory current ownership and define the privilege matrix

- [ ] Inspect `modules/databricks/{account-groups,data-access,catalogs,external-locations,cluster-policies,sql-warehouses}` and their development root inputs.
- [ ] Record each resource/ACL owner, source configuration, principal resolution,
  upstream state dependency, and unmanaged-versus-managed behavior.
- [ ] Define reader, writer, and admin package expansions for each securable type.
  Include parent usage and explicit ownership; do not treat ALL_PRIVILEGES as MANAGE.
- [ ] Retain gold-only SELECT for development readers, isolated operations logs,
  and READ_VOLUME-only init-script access with separately configured parent usage.

Done when: a reviewed matrix states exact grants and explicit exclusions, with no
unknown privilege expansion. Recheck official provider/Databricks documentation.

### A02 — Specify and validate the configuration contract

Depends on A01.

- [ ] Define a versioned YAML contract with stable logical keys, meaningful
  descriptions, explicit environment selection, principal registry, ownership,
  schema/package declarations, and optional explicit grants.
- [ ] Choose one decoding path that feeds existing typed Terraform interfaces.
  Keep provider/backend configuration and credentials outside the contract.
- [ ] Reject unknown fields, duplicate object keys, undeclared principals,
  incompatible packages, invalid privileges, and conflicting owners.
- [ ] Reject `*` and `account users` by default; define reviewed exceptions with
  rationale, scope, target environment, and expiry/review date.
- [ ] Define unmanaged, managed, and intentional-revocation semantics. Preserve
  existing empty-map behavior for legacy callers.

Done when: an example and validation contract are documented; invalid-input
fixtures fail clearly, and configuration reordering leaves identity unchanged.

### A03 — Implement the optional development adapter

Depends on A02.

- [ ] Wire account-group references through `environments/dev/02-account` outputs
  and `environments/dev/03-data-access`; explicitly register pre-existing identities.
- [ ] Expand and consolidate package grants before passing them to existing
  modules. Keep the learning catalog in data-access and additional catalogs in
  the generic composition; reject overlapping ownership.
- [ ] Preserve existing raw grant-map inputs as a compatibility path. Reject two
  competing configuration sources for the same securable.
- [ ] Preserve existing Terraform addresses and group memberships; produce an
  access preview containing principal, environment, securable, and privileges.

Done when: mocked tests demonstrate legacy equivalence, opt-in package expansion,
unknown-principal failure, overlap rejection, broad-access rejection, stable keys,
and explicit grant-removal semantics. Do not apply Terraform to demonstrate this.

### A04 — Enforce review and environment promotion

Depends on A03. Repository-host configuration is a separately authorized action.

- [ ] Add local/CI configuration validation and an effective-access change report.
  Report additions, removals, broader inherited access, and ownership changes.
- [ ] Define CODEOWNERS/review routing for schema owners and platform-owned
  principal registries, package definitions, and broad-access exceptions.
- [ ] Document required branch protection and approval settings; CODEOWNERS alone
  is not proof that approval is enforced.
- [ ] Separate development selection from future staging/production promotion.
  Do not mark those environments runnable or enable automatic production apply.

Done when: validation failures block the chosen workflow, review requirements
are documented, and production access cannot be inferred from development intent.

### A05 — Define deterministic compute personas, if needed

Depends on A02; follow-up beyond the initial schema delivery.

- [ ] Keep workspace roles, SQL entitlements, policy use, warehouse ACLs, and UC
  packages independent in the configuration model.
- [ ] Consolidate ACLs once per compute object in `04-workspace`.
- [ ] Deduplicate repeated declarations; reject conflicting warehouse permission
  levels rather than selecting the first entry. Require unambiguous object lookup.
- [ ] Fail on missing principals/resources instead of silently omitting them.

Done when: reversing persona order produces identical permissions; conflict and
ambiguous-lookup tests fail; readonly identities receive no implicit data writes.
No running cluster or job is needed to test permission generation.

### A06 — Add a scoped path for sensitive table access

Depends on A01 and A03; gated on a real table-access requirement.

- [ ] Identify a dataset needing narrower access than its schema and decide
  whether a separate schema or table/view grants best meets that requirement.
- [ ] Keep table creation with its application; define who owns its grants and
  how access deployment waits for the object to exist without a reverse state read.
- [ ] Ensure parent SELECT does not already grant the access intended to be
  restricted. Table-level grants cannot subtract inherited schema access.
- [ ] Keep filters, masks, and ABAC deferred to a separate ADR and verified use case.

Done when: a concrete example has one grant owner, explicit parent usage, documented
effective inheritance, and grant-removal/lifecycle coverage. If no requirement
exists, leave this item deferred; do not create a general table framework.

### A07 — Review infrastructure access packages independently

Depends on A01; follow-up when ingestion/egress is introduced here.

- [ ] Map publisher, ingestion, and egress needs to bucket/prefix-scoped IAM,
  credentials, locations, and volume access using existing module boundaries.
- [ ] Make delete, replication, versioning changes, and direct file access explicit
  capabilities rather than generic writer defaults.
- [ ] Keep KMS opt-in and secrets out of configuration and preview artifacts.
- [ ] If application-triggered payloads are introduced, bind team/app claims to
  an authorized repository identity; input validation alone is not authorization.

Done when: permissions match the actual workload, negative cases reject broader
scope, and direct AWS access is documented separately from UC table access.

## Reference-only findings to verify separately

These were observed in `work/DB`, not established as defects in this foundation:

| Finding | Follow-up in the reference codebase |
| --- | --- |
| Reader/writer expansion hidden in a private module | Obtain its source and verify privileges, parent usage, and readonly identities |
| Wildcard schema readers and all-user development volume readers | Inventory intentional exceptions and require scoped review |
| Schema CI requests automatic apply for dev/acc/prod | Verify enforced merge approvals and explicit promotion policy |
| Persona merge appends warehouse entries and grant lookup takes the first match | Reject conflicts and test order independence |
| Team validation uses the prod metadata changelog | Verify checks for every target environment and actual identity resolution |
| General table/filter/mask configuration absent from inspected files | Establish a real fine-grained access need before extending the model |

## Verification and completion

For future implementation, run the repository-required Terraform formatting and
TFLint checks. For every changed module, run backend-disabled initialization,
mocked Terraform tests, format checks, and `git diff --check` per AGENTS.md.
Add focused fixtures for the contract and expansion layer. Mocked tests establish
generated grants; they do not establish effective live Databricks permissions.

Before completion, verify:

- Existing opt-out callers retain their inputs, addresses, and access behavior.
- Readers retain gold-only SELECT; operations/log and init-script grants remain scoped.
- Invalid identities, broad defaults, duplicate ownership, and merge conflicts fail.
- Empty configuration is not presented as an implicit revoke-all mechanism.
- No reverse state dependency, provider configuration in reusable modules, or
  newly runnable staging/production claim is introduced.
- Module/root README.md and AGENTS.md document any new modules or environments.

Rollback: retain the raw-map path and compare normalized grants before adoption.
If live ownership must move, prepare a separately reviewed state migration.
Reverting code alone does not restore deleted objects or revoked permissions.

## Handoff for a future Codex session

Read AGENTS.md, ADR 0001, and this backlog; recheck current code before starting.
Implement A01–A03 first when the user authorizes implementation. Complete one
bounded item at a time and record evidence and remaining work here. Treat A05–A07
as gated follow-ups, not requirements to build speculative frameworks.

This document authorizes no Terraform apply, destructive change, remote-state
mutation, production rollout, external-directory edit, or running compute.
Reference-source availability must not block improvements grounded in this
foundation's own code. Report any prerequisite that cannot be verified.
