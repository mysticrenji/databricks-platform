# Platform administrator inputs

## Persona compute

The dev/demo compute runner compiles compute/dev.yaml and access/roles.yaml into
root04 after workspace entitlements, using verified root02 account groups.
Engineers use engineering-standard; ML uses ml-standard; analysts use analytics
SQL without a cluster policy. Membership and data grants remain separate.
See the [compute guide](../tools/databricks-access/COMPUTE.md) for rendering,
deployment, ownership checks, warehouse costs and retirement order.

## Workspace features before dataset access

Dev/demo provisioning runs `01-infra → 02-account → 02-workspace-access → 04-workspace compute`.
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
plan, provisioning opt-in and the dev/demo single-admin policy: manual dispatch
on main by an administrator with deploy=true and confirm_environment=dev/demo.
Dev/demo deprovision uses verified admin/manual/main checks, the separate destroy
opt-in and exact dev/demo confirmation without reviewers, and retires features
before account groups; a dev/demo dry run previews compute and feature retirement.
Other targets are unchanged. No implicit adoption, state migration or live apply
is performed during development. See the [feature runner guide](../tools/databricks-access/README.md).


This folder holds administrator-owned declarations. Consumer requests live in
[`../workloads/`](../workloads/README.md). Paths below are relative to
`AWS/databricks-foundation/`.

```text
platform/
  environments/
    dev/                    # demo.yaml, shared.yaml, sandbox.yaml
    staging/                # shared.yaml
    production/             # Per-team templates, configuration-only
  compute/
    dev.yaml                # Approved runtimes, node types, limits and warehouses
  access/
    roles.yaml              # Personas and exact permission packages
    reviewers.yaml          # Future platform/data-owner approval mappings
    principals/dev/demo.yaml
    resources/dev/demo.yaml  # Workload-to-group bindings and dataset limits
    targets/dev/demo.yaml    # Workspace/account/metastore binding
  terraform-inputs/
    dev/demo.01-infra.json
    dev/demo.02-account.json
```

`platform/environments/` contains AWS/workspace provisioning YAML.
Top-level `environments/` contains executable Terraform roots. These have
different purposes: the Python provisioning adapter reads YAML and passes
validated values to the Terraform code.

`platform/terraform-inputs/` contains optional JSON values for settings not
exposed by environment YAML yet. The adapter combines each workspace's YAML
with its matching `<workspace>.<root>.json`. Demo infra JSON is empty; demo account
JSON explicitly declares the four bootstrap groups and workspace USER/ADMIN roles.
These files contain no Terraform code, provider credentials or state. Only
reviewed supplemental fields are allowed; they cannot override YAML-owned
settings. Keep them until required settings have a validated YAML equivalent.
Moving this folder does not move a Terraform backend or change state keys.

Provisioning root 02 creates `dev-demo-admins` (ADMIN), `dev-demo-engineers`,
`dev-demo-analysts` and `dev-demo-ml` (USER), with external membership. No dataset
or compute prerequisite is needed. The registry uses `lifecycle: terraform`;
root 05 references the root 02 group IDs and never manages their assignments or
entitlements. Offline validation rejects names/roles that disagree with the JSON
and conflicting lifecycle declarations. Other workspace inputs remain unchanged.

Platform personas describe compute access. Workload authors request a matching
persona and data access only. The offline example reads `platform/access/` and
`platform/compute/`, resolves platform-owned workload/group bindings, and checks
consumer requests against those limits. That preview remains offline; the separate
compute runner verifies live identity/availability and plans/applies root04 in trusted CI.
See [access example instructions](../tools/databricks-access/README.md).

## Local validation

From `AWS/databricks-foundation/`:

```bash
python3 -m pip install -r tools/environment/requirements.txt
python3 tools/environment/environment.py validate platform/environments/dev/demo.yaml
python3 tools/databricks-access/access.py validate --environment dev --workspace demo
python3 tools/databricks-access/access.py preview --environment dev --workspace demo
```

Use the [environment guide](../tools/environment/README.md) for an isolated venv,
rendering, provisioning CI and staging support. Production remains
configuration-only. The access example currently supports dev/demo only.

## Updating existing GitHub variables after the folder move

The old environment/compute/registry/supplemental files moved together. File
contents, workspace identities, backend keys and cloud resource ownership did
not change. Provision/deprovision defaults and the GitHub setup helper now use
`platform/environments/`. A saved GitHub `ENVIRONMENT_CONFIG_PATH` takes precedence
over the default, so update it in both environments for each affected workspace.

For the dev/demo pair, run this when ready to update GitHub settings:

```bash
for phase in plan apply; do
  gh variable set ENVIRONMENT_CONFIG_PATH \
    --repo mysticrenji/databricks-platform-engineering \
    --env "dev-demo-${phase}" \
    --body 'AWS/databricks-foundation/platform/environments/dev/demo.yaml'
done
```

This updates only the path and preserves apply/destroy opt-ins. Adapt the target
names/path for other workspaces and custom YAML filenames. Alternatively rerun
the [setup helper](../tools/github-environment-setup/README.md) with the new path;
remember that omitted enable flags reset their opt-ins to false. No external
GitHub variables were updated by the folder refactor itself.

Regenerate saved Terraform plans/destroy previews after merging this source
change. Do not use backend migration, state moves or resource recreation for a
configuration-folder move. Keep the deployment and access approval boundaries
described in [ADR 0005](../docs/adr/0005-api-driven-access-and-compute.md).
