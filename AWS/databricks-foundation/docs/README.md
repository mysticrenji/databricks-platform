# Architecture and future work

These documents record proposed configuration interfaces for environment
provisioning and access management. Environment provisioning is the first delivery
priority; schema access and personas follow separately.

Administrator inputs are organized under [`platform/`](../platform/README.md):
provisioning YAML, compute definitions, access rules and supplemental Terraform
inputs. Consumer declarations remain in `workloads/`; Terraform code stays in
`environments/` and `modules/`. The move changes file paths, not state namespaces.

- [ADR 0005: API-driven access and compute](adr/0005-api-driven-access-and-compute.md)
  is the accepted next-phase design: platform-owned persona/compute YAML and
  workload-owned persona/data declarations under foundation-local `workloads/`,
  reconciled by Python through reviewed CI. Compute selection stays in platform personas.
  It specifies ownership, exact privilege packages, example contracts, inventory,
  revocation, shared-metastore handling, migration and teardown integration.
- [API access and compute implementation checklist](plans/api-access-and-compute-action-items.md)
  is the current Codex handoff. The first [dev/demo offline example](../tools/databricks-access/README.md)
  implements strict validation, desired-state previews and credential-free CI.
  Live API planning, ownership adoption and apply remain pending.

- [ADR 0004: Environment/workspace isolation](adr/0004-environment-workspace-isolation.md)
  defines the current version-2 YAML contract, per-workspace GitHub Environments,
  state namespaces, naming, and adoption after teardown.

- [ADR 0002: Environment YAML provisioning](adr/0002-environment-yaml-provisioning.md)
  records the environment YAML adapter, Python validation, and CI execution of the
  existing infrastructure and workspace-creation Terraform roots.

- [ADR 0003: GitHub Actions deprovisioning](adr/0003-github-actions-deprovisioning.md)
  describes a manual, approved workflow that calls Terraform destroy in reverse
  dependency order while retaining S3 and KMS resources. The
  [operational guide](../tools/environment/DEPROVISIONING.md) covers configuration,
  previews, approvals, retention, and recovery. No live teardown was performed
  during implementation.

- [ADR 0001: Configuration-driven access management](adr/0001-configuration-driven-access-management.md)
  is historical and superseded by ADR 0005.
- [Access management action items](plans/configuration-driven-access-action-items.md)
  retains the superseded Terraform-adapter backlog for reference.

Environment provisioning is implemented with deployment adoption pending. Access
management has an offline example only. Documentation approval does not authorize
Terraform applies, remote-state changes, or edits to the reference directory.
