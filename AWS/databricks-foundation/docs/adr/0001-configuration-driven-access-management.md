# ADR 0001: Configuration-driven access management

- Date: 2026-10-14
- Status: Superseded by ADR 0005; retained as historical context
- Scope: This Databricks AWS foundation
- Execution backlog: [Access management action items](../plans/configuration-driven-access-action-items.md)

> The current decision is [ADR 0005: API-driven access and compute](0005-api-driven-access-and-compute.md).
> It replaces this ADR's Terraform-owned access adapter with Python/SDK ownership
> for explicitly adopted scopes. Do not implement this historical proposal as the
> current architecture or change existing Terraform ownership without adoption.

## Context

The user requested that the findings from a review of the external `work/DB`
directory be saved as future action items with an ADR. The reference directory
is a separate codebase, identified relative to the operator's workspace, not a
dependency of this repository.

The reference uses team/persona YAML for workspace and compute permissions,
one YAML file per schema for writer/readers, and application payloads for
ingestion/egress infrastructure. GitLab CODEOWNERS delegates schema review to
teams. Its private schema module was not available locally, so the exact
reader/writer privilege expansion and team-to-principal resolution were not
verified. Live permissions and GitLab approval settings were not inspected.

This foundation already provides typed Terraform inputs, authoritative UC grant
maps, account groups, and four separate deployment roots. It does not need a
replacement provisioning framework. It needs an optional configuration layer
that makes access intent easier to review without obscuring effective grants.

Existing implementation anchors:

- `modules/databricks/account-groups/variables.tf`: account groups keyed by
  display name with workspace roles and optional delegated group managers.
- `environments/dev/02-account/outputs.tf`: exports `account_group_ids`.
- `modules/databricks/data-access/variables.tf`: catalog, schema, incoming
  volume, and operations grants.
- `modules/databricks/catalogs/main.tf`: one authoritative grants resource per
  configured catalog, schema, or volume; empty grant maps leave grants unmanaged.
- `environments/dev/03-data-access/main.tf`: generic catalogs and the data-access
  composition share phase three but must never own the same UC object.

## Proposed decision

Add an opt-in, versioned configuration contract above existing Terraform modules.
Start with schemas and account-group access packages. Keep Terraform as the
resource and state owner. YAML is a proposed authoring format; validate decoded
input before passing it to typed module interfaces. Do not introduce CDKTF or a
second resource-management system.

1. **Separate access planes.** Distinguish AWS IAM/S3 access, account/workspace
   assignment, compute ACLs, UC data privileges, and object ownership. A workspace
   ADMIN role, group-manager role, and UC MANAGE privilege remain independent.
2. **Expose effective privileges.** Define reader/writer/admin packages by
   securable type, including necessary parent usage. Reader does not imply
   workspace SQL access, compute access, volume access, or storage-credential use.
   Ownership is an explicit field, never a side effect of a writer package.
3. **Resolve declared identities.** Configuration references logical principal
   keys resolved to account identities. New group-backed packages use phase-two
   groups; externally managed groups or service principals require an explicit
   registry. Do not silently skip missing identities or manage IdP memberships.
4. **Preserve least privilege.** Keep readers' SELECT scoped to gold in the
   existing development example. Reject wildcard/all-account-user access by
   default. Exceptions require explicit environment, scope, rationale, and review.
5. **Keep schema sharing intentional.** Schema SELECT applies to current and
   future tables/views. Separate schemas when their sharing requirements differ.
   Narrow table grants cannot undo broader inherited access.
6. **Preserve one owner per securable.** Merge package expansions into a single
   authoritative ACL before passing it to a module. Reject duplicate ownership
   across generic maps, data-access composition, and any future table-grant layer.
7. **Make promotion explicit.** Produce an effective-access preview per
   environment. Shared configuration must not silently promote development
   access to production. A future production pipeline needs enforced approvals.
8. **Handle conflicts deliberately.** Deduplicate compatible package grants;
   reject conflicting single-valued warehouse ACLs or ownership declarations.
   File/persona ordering must not decide permissions.
9. **Keep tables with applications.** Application pipelines/dbt retain table
   creation and lifecycle. Add table-specific access only after a concrete use
   case establishes the grant owner and object-existence ordering. Row filters,
   masks, and ABAC require a later scoped decision.

## State and deployment boundaries

| Root | Continues to own |
| --- | --- |
| 01-infra | AWS networking, infrastructure IAM, and S3 buckets |
| 02-account | Account configuration, workspace creation, account groups, budgets |
| 03-data-access | Metastore assignment, UC IAM roles, credentials, locations, catalogs, schemas, volumes, UC grants |
| 04-workspace | Workspace bootstrap, instance profiles, compute policies, warehouses, jobs, compute ACLs |

Deploy whole roots in order 01 → 02 → 03 → 04. Add no reverse remote-state read.
Provider configuration stays in roots. Preserve backend keys, resource addresses,
admin memberships, and the retired-deployment initialization rules in AGENTS.md.
Staging and production remain scaffolds until separately implemented.

## Alternatives considered

- **Keep only raw grant maps:** simplest implementation and retained as a
  compatibility path, but repeated mappings are harder for teams to review.
- **Copy the reference implementation:** rejected as a default. It relies on
  private modules, organization-specific identifiers, and a second Terraform
  authoring framework, with different state boundaries.
- **Manage every table centrally in Terraform:** deferred. It couples platform
  access provisioning to application table lifecycle and needs a concrete owner.

## Consequences

The layer adds validation and maintenance, but can make requests, reviews, and
effective permissions traceable. Schema inheritance reduces repetitive grants
while making schema boundaries more consequential. Authoritative ACLs can remove
manual grants, so ownership and removal behavior must be visible before adoption.

Empty-map behavior needs special care: today an empty map means unmanaged grants,
not an explicit instruction to revoke every grant. A future contract must
distinguish unmanaged, managed, and intentional revocation, and verify provider
behavior without silently changing existing callers.

## Preconditions for implementation

Confirm the contract and package matrix in the backlog before wiring configuration.
Re-read current code and provider documentation; this ADR records a review snapshot.
State migration, destructive changes, and applies require explicit authorization.
No reference-code defect is assumed to exist in this foundation.

## Sources

Reference review anchors, relative to the external `work/DB` directory:

- `schemas/terraform/locals.tf`, `main.tf`, and `external.tf`.
- `schemas/validation/schema.json`, `src/validate_grantees.py`, and `src/codeowners.py`.
- `schemas/.gitlab/terraform.yml`.
- `teams/src/config.py` and `src/databricks_stack.py`.
- `capabilities/terraform/modules/ingestion_s3/locals.tf` and `ingress_storage.tf`.

[Unity Catalog privilege reference](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/privileges-reference)
documents schema privilege inheritance and parent usage requirements. Reverify
privilege support against the pinned provider at implementation time.
