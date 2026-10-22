# ADR 0002: Environment YAML for AWS and workspace provisioning

> The original version-1 examples below are historical. The current version-2
> contract and workspace state isolation are defined in
> [ADR 0004](0004-environment-workspace-isolation.md). Use the current
> [adapter guide](../../tools/environment/README.md) for executable commands.

- Date: 2026-10-15
- Status: Implemented on feature branch; deployment adoption pending
- Scope: Environment inputs, Python validation, and CI orchestration for AWS infrastructure and Databricks workspace creation
- Related: [ADR 0001: Configuration-driven access management](0001-configuration-driven-access-management.md)

## Context

The foundation already has reusable Terraform modules and four separately managed
roots. Routine environment setup still requires understanding multiple Terraform
input files. The desired interface is one readable YAML document per environment,
validated before CI executes Terraform.

Environment provisioning answers what infrastructure and workspace should exist.
Schema access answers who can read or write data. Compute personas answer which
approved capabilities a team can use. These are separate concerns; provisioning
does not depend on implementing the other two.

Current implementation anchors:

- `environments/dev/01-infra`: AWS networking, roles, workspace root storage,
  landing/managed-data buckets, and optional infrastructure features.
- `environments/dev/02-account`: Databricks account registrations and workspace
  creation; reads infrastructure outputs through remote state.
- `environments/dev/03-data-access`: metastore assignment, UC storage integration,
  catalogs, schemas, volumes, and grants.
- `environments/dev/04-workspace`: workspace bootstrap and compute configuration.
- `modules/aws/data-storage/main.tf`: generates landing and managed bucket names.
- `modules/aws/egress` and root inputs: explicit subnet maps and same-AZ NAT
  mappings, rather than a `single`/`per_az` mode switch.
- `modules/databricks/account-budgets`: Databricks spending alerts, not AWS Budgets.

Development is the first implementation target. Staging and production are
scaffolds and do not become deployable by supplying YAML.

## Decision

Introduce a versioned environment YAML contract above the existing Terraform.
Use Python to validate and translate it into root-specific JSON variable files.
Terraform remains the only infrastructure/resource and state owner. Do not
generate Terraform resource definitions or replace the existing modules.

The first delivery covers roots `01-infra` and `02-account` for shared dev and
staging only. Preserve root directories, resource addresses, provider aliases,
backend keys, and remote-state dependencies. No merged state or reverse
dependency is introduced.

### Configuration ownership and scope

Store the source documents under `platform/environments/`: a shared development
and staging document, plus production documents for analytics, data-engineering,
and ML platform. The development document is
`platform/environments/dev/environment.yaml`. It owns the exposed
infrastructure/workspace settings for that deployment. Generate
complete inputs for those settings; do not merge competing YAML and hand-edited
tfvars values by undocumented precedence. A legacy invocation can continue to
use existing tfvars, but the YAML execution path must isolate its generated
inputs from automatically loaded legacy `.tfvars`/`.auto.tfvars` files and reject
conflicting `TF_VAR_*` or CLI overrides.

Keep the initial fields close to existing module inputs. Include explicit,
stable subnet keys and CIDRs rather than adding an automatic network allocator.
For example, this is a proposed contract, not an executable configuration today:

```yaml
version: 1
environment:
  name: dev
  aws_account_id: "111111111111"
  aws_region: eu-west-1
  deployment_role_arn: arn:aws:iam::111111111111:role/databricks-dev-terraform
databricks:
  account_id: "00000000-0000-0000-0000-000000000000"
  workspace_name: acme-dev
  pricing_tier: PREMIUM
network:
  vpc_cidr: 10.40.0.0/16
  workspace_subnets:
    a: {availability_zone: eu-west-1a, cidr_block: 10.40.0.0/20}
    b: {availability_zone: eu-west-1b, cidr_block: 10.40.16.0/20}
  nat_subnets:
    a: {availability_zone: eu-west-1a, cidr_block: 10.40.32.0/24}
    b: {availability_zone: eu-west-1b, cidr_block: 10.40.33.0/24}
  workspace_subnet_nat_gateway_keys: {a: a, b: b}
  endpoint_subnets:
    a: {availability_zone: eu-west-1a, cidr_block: 10.40.34.0/24}
    b: {availability_zone: eu-west-1b, cidr_block: 10.40.35.0/24}
storage:
  workspace_bucket_name: replace-me-acme-dev-workspace
features:
  customer_managed_kms: false
  observability: true
```

The validator rejects placeholder values for deployment. An eventual checked-in
example fixture can use them only in an explicitly non-deployable example mode.
Supported optional fields and defaults must be documented in the schema; defaults
must match current behavior. YAML ordering must not change Terraform identities.

### Deferred fields

- `governance.catalog_name` and `catalog_storage_prefix`: defer to root 03 work.
  Creating an S3 managed-data bucket in root 01 does not create a UC catalog.
- Custom `catalog_bucket_name`: requires an explicit, backward-compatible input
  in data-storage and root wiring. Initially retain existing generated names.
- `nat_gateway_mode: single`: defer until networking behavior and validation are
  implemented. Preserve the current explicit same-AZ mappings in version 1.
- `aws_monthly_budget_usd`: requires AWS Budgets implementation. Do not translate
  it into the existing Databricks budget input. Budget alerts are separate from
  spending limits; Databricks alerts may be exposed later under an explicit name.
- Account-group memberships, schema grants, personas, compute policies, jobs and
  workspace entitlements: continue through existing paths; do not change them as
  a side effect of introducing environment YAML.

Unsupported fields fail validation rather than being accepted and ignored.

### Python validation and translation

Provide a local/CI command with two steps: validate, then render. Use a safe YAML
parser with duplicate-key rejection, a strict JSON Schema, and small Python
semantic checks. JSON Schema replaces the proposed Pydantic model to keep the
implementation explicit and usable without a model framework. Pin dependencies and use the same validator locally
and in CI. Forbid unknown fields at every nesting level; reject implicit type
coercion such as numeric account IDs or string booleans.

Before cloud authentication or Terraform execution, validate:

- Schema version, supported environment, required fields, types, and enum values.
- Account IDs, deployment-role ARN/account agreement, names, and placeholders.
- CIDR syntax, subnet containment and overlap, at least two workspace AZs,
  regional AZ naming, and same-AZ NAT mapping consistency.
- Supported feature combinations; in particular, reject PrivateLink activation
  while Databricks-specific PrivateLink provisioning remains unimplemented.
- Environment-to-root selection and reviewed region/feature support constraints.
- Absence of credential fields; YAML contains identifiers, never access keys,
  tokens, or client secrets.

Offline validation cannot prove bucket-name availability, AWS permissions,
Databricks entitlements, AZ availability, or quotas. After authentication, verify
the effective AWS account and configured Databricks account target before plan.
Cloud checks and Terraform validation/plan remain necessary.

Render deterministic `01-infra.tfvars.json` and `02-account.tfvars.json` into an
isolated build directory. Keep the mapping explicit, such as
`network.vpc_cidr` to `vpc_cidr_block` and `storage.workspace_bucket_name` to
`root_storage_bucket_name`. Runtime resource IDs continue to come from Terraform
outputs/remote state, not generated copies or YAML. Generated files are build
artifacts, not an additional hand-maintained source of truth.

### CI and deployment flow

1. Validate the selected YAML without cloud credentials. Run adapter fixtures,
   repository checks, backend-disabled initialization and Terraform validation.
2. Render inputs and record the source commit, YAML digest, adapter version and
   generated-input digests for reproducibility.
3. In an authorized plan job, authenticate using short-lived AWS credentials and
   Databricks OAuth/workload federation. The YAML role is a target identifier,
   not authority to assume an arbitrary role. Bind allowed environments/accounts/
   roles to trusted CI configuration and the cloud trust policy. Do not expose
   deployment credentials to untrusted pull-request execution.
4. Initialize each root with its existing backend configuration. Backend settings
   and CI authentication bindings remain separately controlled; tfvars cannot
   configure a Terraform backend. The state bucket must already exist.
5. Plan root 01. An authorized deployment applies its saved, reviewed plan, then
   plans root 02 against the updated upstream state. For a new environment, root
   02 cannot produce a meaningful plan before root 01 has produced its outputs.
   Existing-state previews before an upstream apply are provisional.
6. Apply root 02 only through the configured deployment approval flow, using its
   saved plan. Changes to source, inputs or upstream state require a fresh plan
   and any required review. Never treat a YAML merge as implicit apply approval.

Serialize deployment per environment, retain state locking, stop after failures,
and protect plan artifacts because they can contain sensitive values. Apply
whole roots; do not use `-target`. Keep roots 03 and 04 outside this workflow.

No existing backend is migrated automatically. Provisioning new environments
requires implemented roots and explicitly registered CI/backend bindings.

## Alternatives considered

- Keep only tfvars: lowest maintenance, but leaves environment authors coupled
  to multiple root-specific interfaces. Retain this as the legacy path.
- Decode YAML directly in every Terraform root: avoids a compiler but spreads
  parsing/mapping and does not supply the requested Python preflight boundary.
- Generate HCL or introduce another provisioning framework: unnecessary; the
  modules already implement the required infrastructure ownership.
- Combine provisioning, schema access and personas in one contract: deferred
  because each has different ownership, validation and deployment requirements.

## Consequences

Environment authors get one reviewed document and early, readable validation
errors. Terraform code still needs changes when a genuinely new capability is
introduced. YAML is an interface, not a way to bypass module support.

The adapter adds a schema, dependency and mapping maintenance obligation. Limit
the exposed surface initially and test it against the current Terraform inputs.
Account/workspace setup remains separate from data and compute access.

## Implementation sequence and acceptance

1. Define the strict version-1 model, field mappings, defaults and example.
2. Implement validation/rendering with fixtures for invalid fields, duplicate
   keys, account/role mismatches, CIDR/AZ errors, unsupported features and stable
   output under key reordering.
3. Wire development root execution without changing resource addresses. Compare
   rendered inputs with an equivalent existing development configuration; verify
   no loss of existing groups, memberships or optional resources through omitted
   legacy inputs. Preserve such inputs through one explicit, reviewed mechanism
   until they have their own contract; block deployment if equivalence is unknown.
4. Add CI validation first, then authorized planning/deployment with serialized
   root ordering, account checks and protected artifacts.
5. Run existing Terraform formatting, lint and relevant mocked module tests per
   AGENTS.md. No live apply is required to verify the adapter.

Done when a developer can validate a dev YAML, generate repeatable inputs, and
obtain plans through the documented sequence, while invalid configurations fail
before provisioning and legacy invocation remains available. Prove override
isolation and deployment gating with focused CI/runner tests.

Rollback before adoption is to retain legacy inputs and remove the opt-in adapter.
After a deployment, reverting YAML/code does not undo created resources or restore
previous infrastructure. Review a new Terraform plan; do not reset remote state.

This ADR authorizes no apply, state mutation, CI trust-policy change, or production
rollout. Schema access and personas remain future work under ADR 0001; environment
provisioning is the first delivery priority.

## Implementation evidence

The adapter, tests and operational instructions live in
[`tools/environment`](../../tools/environment/README.md). The checked-in
development template is `platform/environments/dev/environment.yaml`; real values
must be supplied before deployment. `.github/workflows/environment-validation.yml`
validates the development and staging templates without cloud credentials. The
manual provisioning workflow lets an operator choose development or staging and
executes roots 01 then 02 with separate plan/apply jobs and saved-plan artifacts.
Each environment has its own GitHub environment variables and state keys.
Production remains configuration-only: GitHub Actions does not read it, and the
Terraform runner rejects it. No live deployment was performed.

Existing optional inputs use reviewed, allowlisted
`platform/terraform-inputs/<environment>.*.json` files. These are empty initially, so
existing deployments must carry over their optional inputs and review equivalence
before adoption. This does not migrate existing local tfvars automatically.
Backend settings and deployment bindings remain in trusted CI environments.
Production remains a scaffold.
