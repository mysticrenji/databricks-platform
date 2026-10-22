# Databricks Platform Engineering

Infrastructure and configuration for building and operating a Databricks platform
on AWS with Terraform, Python, and GitHub Actions.

The project separates cloud infrastructure, workspace provisioning, data governance,
and compute into independently managed layers. Platform administrators define
approved settings in YAML, while teams declare their persona and data-access
needs through workload configuration.

## What the project covers

- **AWS foundation:** networking, IAM, S3 storage, optional encryption, and monitoring.
- **Databricks workspaces:** account configuration, workspace creation, groups,
  workspace access, and budget alerts.
- **Data governance:** Unity Catalog integration, storage access, and permissions
  on existing data objects.
- **Compute configuration:** persona-based cluster policies, SQL warehouses, and
  workspace jobs through reusable Terraform modules.
- **Operations:** offline validation, Terraform planning, explicit deployment,
  read-only diagnostics, and controlled deprovisioning.

## How it works

Platform configuration lives alongside reusable Terraform modules and separate
execution roots. Each root owns a distinct Terraform state so infrastructure,
workspace identity, access, data objects, and compute have clear ownership.

GitHub Actions runs credential-free validation and mocked tests on pull requests
and relevant main-branch pushes. Provisioning, deprovisioning, permissions planning,
and live diagnostics are manual operations. Deployment uses saved Terraform plans
and explicit opt-ins, with approval requirements defined by the target environment.

## Repository layout

```text
AWS/databricks-foundation/     Active AWS implementation
  platform/                   Administrator-owned YAML and supplemental inputs
  workloads/                  Team persona and data-access requests
  environments/               Terraform roots with separate state
  modules/                    Reusable AWS and Databricks modules
  tools/                      Python validation and lifecycle runners
  docs/                       Architecture decisions and implementation guides
.github/workflows/            CI and manual operational workflows
Azure/                        Placeholder for future Azure work
```

The current automation focuses on the AWS dev/demo workspace. Environment
provisioning also supports development and staging targets; the persona compute
and permissions runners currently support dev/demo only. Production templates
are configuration scaffolds, and Azure has no implementation yet.

## Start here

Read the [AWS foundation guide](AWS/databricks-foundation/README.md) for setup,
deployment order, prerequisites, and validation commands.

| Guide | What it explains |
| --- | --- |
| [Platform configuration](AWS/databricks-foundation/platform/README.md) | Environment YAML, personas, and approved compute |
| [Workload configuration](AWS/databricks-foundation/workloads/README.md) | Team requests for persona and data access |
| [Provisioning](AWS/databricks-foundation/tools/environment/README.md) | Configuration validation and manual deployment |
| [Access and permissions](AWS/databricks-foundation/tools/databricks-access/README.md) | Ownership, data grants, CI, and diagnostics |
| [Compute](AWS/databricks-foundation/tools/databricks-access/COMPUTE.md) | Persona policies and SQL warehouses |
| [Deprovisioning](AWS/databricks-foundation/tools/environment/DEPROVISIONING.md) | Teardown, storage retention, and optional storage purge |
| [Architecture and decisions](AWS/databricks-foundation/docs/README.md) | Design rationale and operational boundaries |
