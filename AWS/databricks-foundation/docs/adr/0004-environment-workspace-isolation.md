# ADR 0004: Separate environments and workspaces

- Date: 2026-10-16
- Status: Implemented on feature branch; live adoption pending
- Scope: Deployment identity, configuration, GitHub Environments, state, and resource naming
- Related: [Provisioning](0002-environment-yaml-provisioning.md), [deprovisioning](0003-github-actions-deprovisioning.md)

## Context

One shared workspace per environment meant every dev YAML used the same GitHub
Environments and Terraform state bindings. Changing the config filename could
therefore modify an existing workspace instead of creating another independent
deployment. The previous dev deployment has been deprovisioned, allowing a
fresh namespace without migrating live resources. Retained S3/KMS resources
from teardown are still independently owned and must not be assumed deleted.

## Decision

Version 2 requires separate `environment.name` and `workspace.name` fields.
Environment is dev, staging, or production; workspace is a stable lowercase
slug, at most 16 characters. The bounded length keeps generated AWS names within
service limits. Databricks workspace names are derived as `<environment>-<workspace>`.
Remove the old `databricks.workspace_name` field rather than maintaining two
independent workspace names. Production remains unavailable to Actions.

For dev/sandbox:

| Concern | Binding |
| --- | --- |
| Default YAML | `platform/environments/dev/sandbox.yaml` |
| Optional infra inputs | `platform/terraform-inputs/dev/sandbox.01-infra.json` |
| Optional account inputs | `platform/terraform-inputs/dev/sandbox.02-account.json` |
| Cloud workspace | `dev-sandbox` |
| GitHub Environments | `dev-sandbox-plan`, `dev-sandbox-apply` |
| AWS name prefix | `databricks-dev-sandbox` |
| State prefix | `databricks/dev/sandbox/` |
| Concurrency group | `databricks-environment-dev-sandbox` |
| Destroy confirmation | `dev/sandbox` |

All four state keys end with their root name plus `.tfstate`. The helper derives
them, and both provisioning and deprovisioning reject cross-namespace overrides.
The same bucket and deployment role can serve multiple workspace namespaces.
Root 01 exports its identity; root 02 checks it before reading infrastructure
outputs. Provider tags and generated AWS names include both identifiers.

Both manual workflows select an environment and workspace. Their concurrency
groups match for that pair. Saved artifacts bind the complete config and backend;
another workspace cannot consume them. Destroy still retains S3/KMS resources
and checks downstream roots 03/04 at that workspace's namespaced keys.

`ENVIRONMENT_CONFIG_PATH` remains an optional per-pair override, allowing a file
such as a custom YAML filename to declare dev/demo. The filename does not select
state; the validated YAML identity and workflow selection must agree. The setup
helper requires `--workspace`, creates the corresponding GitHub Environment
pair, and fills all four state variables. Approvals and AWS OIDC trust must be
configured for the new names; old dev-plan/dev-apply subjects are not equivalent.

The supplied examples are dev/shared, dev/sandbox, staging/shared, and the
dev/demo file. Production examples adopt separate identity
fields for future use, but Actions does not read or execute them.

## Adoption and rollback

Version 1 config and old environment-only keys are intentionally rejected. This
feature does not migrate, overwrite, or delete old state or GitHub Environments.
Reverting code before adoption restores the old contract. After provisioning,
reverting does not migrate the new namespaces back; review state ownership first.
Existing live deployments require a separate migration plan.

Retained buckets and keys remain in AWS after deprovisioning. The demo
YAML uses a fresh workspace bucket name and generated resource prefixes now
include workspace identity. Never reuse old names under fresh state without
reviewing ownership and import. Shared account groups and explicit custom names
in supplemental settings also need a single owner; the adapter does not make
independently managed shared resources safe automatically.

## Validation

Tests cover unique keys and names for two dev workspaces and a staging workspace,
target/YAML mismatch rejection, cross-workspace plan/state rejection, helper
variable generation, root identity handoff, and workspace-specific AWS names.
No cloud apply, destroy, state migration, or GitHub settings change is part of
this implementation.
