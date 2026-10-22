# GitHub Environment setup helper

Create a plan/apply GitHub Environment pair for one **environment plus
workspace**, such as dev/demo or dev/sandbox. The helper reads the AWS role
and Databricks account ID from version-2 YAML. It does not provision or destroy
cloud resources.

Administrator YAML now lives under `platform/environments/`. If existing GitHub
variables still refer to the former folder, update both plan/apply environments
using the [platform migration instructions](../../platform/README.md#updating-existing-github-variables-after-the-folder-move).
The helper's default now uses the new folder; it does not migrate state.

## Prerequisites

Use Python 3.10 or later, GitHub CLI access to manage repository environments,
variables/secrets, real YAML values, and an existing S3 state bucket and AWS role.

From the repository root:

```bash
cd AWS/databricks-foundation
python3 -m venv /tmp/databricks-github-setup
/tmp/databricks-github-setup/bin/pip install -r tools/environment/requirements.txt
gh auth login
```

## Full dev/demo command

The supplied file `platform/environments/dev/demo.yaml` declares `version: 2`,
`environment.name: dev`, and `workspace.name: demo`. Keep its complete
Databricks, network, storage, and feature sections. Cloud name `dev-demo`
is derived; remove the old `databricks.workspace_name` field from custom files.

Preview from the foundation directory:

```bash
/tmp/databricks-github-setup/bin/python tools/github-environment-setup/setup_github_environments.py dev \
  --workspace demo \
  --repo mysticrenji/databricks-platform-engineering \
  --config platform/environments/dev/demo.yaml \
  --state-bucket databricks-platform-nl \
  --state-region eu-central-1 \
  --databricks-client-id 800d9fd2-cd82-402b-b973-85326ee96d5d
```

Add `--execute` to create/update GitHub settings. It securely prompts for
`DATABRICKS_CLIENT_SECRET`, or reads that environment variable. Do not pass
secrets on the command line or commit them to YAML.

From this helper's folder, the equivalent executable command is:

```bash
python3 setup_github_environments.py dev \
  --workspace demo \
  --repo mysticrenji/databricks-platform-engineering \
  --config ../../platform/environments/dev/demo.yaml \
  --state-bucket databricks-platform-nl \
  --state-region eu-central-1 \
  --databricks-client-id 800d9fd2-cd82-402b-b973-85326ee96d5d \
  --execute
```

This creates **dev-demo-plan** and **dev-demo-apply**, with these variables
and the client secret in both:

```text
ENVIRONMENT_CONFIG_PATH=AWS/databricks-foundation/platform/environments/dev/demo.yaml
AWS_DEPLOYMENT_ROLE_ARN=<from YAML>
DATABRICKS_ACCOUNT_ID=<from YAML>
DATABRICKS_CLIENT_ID=<command argument>
TF_STATE_BUCKET=databricks-platform-nl
TF_STATE_REGION=eu-central-1
TF_INFRA_STATE_KEY=databricks/dev/demo/01-infra.tfstate
TF_ACCOUNT_STATE_KEY=databricks/dev/demo/02-account.tfstate
TF_DATA_ACCESS_STATE_KEY=databricks/dev/demo/03-data-access.tfstate
TF_WORKSPACE_STATE_KEY=databricks/dev/demo/04-workspace.tfstate
```

All four keys are derived automatically. Overrides that select another namespace
are rejected. The bucket region is independent of the YAML infrastructure region.

## Add sandbox

Fill in `platform/environments/dev/sandbox.yaml`, keeping
`workspace.name: sandbox`. Change the command to `--workspace sandbox` and
`--config ../../platform/environments/dev/sandbox.yaml` when running from this
folder. With no `--config`, the default is
`platform/environments/<environment>/<workspace>.yaml`.

The pair becomes **dev-sandbox-plan** / **dev-sandbox-apply** and all four keys
use `databricks/dev/sandbox/`. Workspaces can share an AWS account, state bucket,
and deployment role while using separate state and generated resource names.
Give each a unique workspace bucket and supplemental inputs; see the
[adapter guide](../environment/README.md).

## Enable execution

Configure required reviewers and deployment branch restrictions on each new
apply environment. Update AWS OIDC trust for the new environment names,
preserving immutable owner/repository IDs in its subjects. The helper does not
configure approvals or AWS trust.

Add these flags to the setup command as needed:

- `--enable-apply --execute` sets `ENVIRONMENT_YAML_APPLY_ENABLED=true` on the
  apply environment. Also select **Apply reviewed plans** when dispatching CI.
- `--enable-destroy --execute` sets `ENVIRONMENT_YAML_DESTROY_ENABLED=true`.
  Deprovision confirmation now includes both identifiers, such as `dev/demo`.
- Pass both to enable both. Each omitted flag writes `false`, including repeat
  runs. No enable flags are added to plan environments.

Commit/push YAML and workflows before starting Actions. Select both the matching
environment and workspace. Old dev-plan/dev-apply settings are not migrated or
deleted. Production remains unavailable. See the
[deprovisioning guide](../environment/DEPROVISIONING.md) for retention and recovery.
