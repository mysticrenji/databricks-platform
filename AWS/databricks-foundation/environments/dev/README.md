# Development deployment

The development roots are fully wired. Apply them in order:

1. 01-infra (modules 1–11): AWS networking, workspace roles, root storage,
   Kinesis, observability, and landing/managed-data S3 buckets.
2. 02-account (modules 12–15): workspace creation, account groups, budgets.
3. 03-data-access (modules 16–20): metastore setup, credentials → UC IAM roles →
   external locations → catalogs, medallion schemas, log/init-script volumes.
4. 04-workspace (modules 21–25): workspace identities, instance-profile
   registration, compute policies with logging/scripts, warehouses, jobs.

All UC data objects, including optional generic external_locations/catalogs,
belong to 03-data-access. Do not declare the same remote object twice.

## Before the first apply

Use Terraform 1.10 or later for S3 native lock files. The state bucket must
already exist; enable versioning, encryption, and public-access blocking.
Backend credentials need access to the state objects and their `.tflock`
objects. This repository does not create the backend bucket in the phase that
uses it.

Each folder includes `terraform.tfvars.example`; an ignored `terraform.tfvars`
was also seeded if one did not exist. Replace the Databricks account ID and
unique root-bucket name in phase one. Set the same Databricks account ID in
phases two and three. Replace `state_bucket` in their tfvars with the S3 backend
bucket; `state_region` is its AWS region, not necessarily the workspace region.

Version-2 CI selects an environment plus workspace; see the
[adapter guide](../../tools/environment/README.md). The examples below use
dev/shared. For another workspace, change all four keys consistently and supply
`environment_name` and `workspace_key` to roots 01/02. These are fresh namespace
examples, not a migration of old state. Roots 03/04 remain outside the CI adapter.

Copy each `backend.hcl.example` to `backend.hcl` and replace the bucket name.
Keep these keys consistent with the downstream `infra_state_key` and
`account_state_key`, and `data_access_state_key` values:

| Phase | S3 key |
| --- | --- |
| 01-infra | databricks/dev/shared/01-infra.tfstate |
| 02-account | databricks/dev/shared/02-account.tfstate |
| 03-data-access | databricks/dev/shared/03-data-access.tfstate |
| 04-workspace | databricks/dev/shared/04-workspace.tfstate |

Authenticate AWS through your usual AWS profile or assumed role. Authenticate
Databricks with OAuth M2M or workload identity federation. For M2M, supply
`DATABRICKS_CLIENT_ID` and `DATABRICKS_CLIENT_SECRET` through the environment,
never tfvars. Phase three needs credentials authorized for both account and
workspace operations. Phase four uses workspace authentication. Local backend
files use the existing databricks-foundation/dev/ prefix; examples use databricks/dev/.
Keep each remote-state key aligned with the corresponding backend.

The old states were confirmed empty before this reorder. Reinitialize the two
renamed roots with `terraform init -reconfigure -backend-config=backend.hcl` to
replace cached backend settings. No state migration is needed for this retired
deployment. Other live deployments need a reviewed migration first.

## Run from each phase directory

```bash
cp backend.hcl.example backend.hcl
# Edit backend.hcl and terraform.tfvars first.
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Terraform automatically loads `terraform.tfvars`. Finish phase one before
planning phase two, finish phase two before phase three, and finish data-access
setup in phase three before planning phase four. Destroy
in reverse phase order. Module references and explicit dependencies enforce
resource prerequisites within each state; numbering documents the workflow,
not a requirement to apply individual child modules separately.

## Unity Catalog and workload prerequisites

Set `existing_metastore_id` to assign an existing regional metastore, or set
`create_metastore = true` only if a new regional metastore is needed. With both
unset, the existing workspace assignment is left alone. New catalogs require
managed storage: this root creates a metastore without a shared root, so provide
catalog-level storage roots governed by existing external locations and storage
credentials. The data-storage module provisions S3 in infra; 03-data-access provisions UC
roles, credentials, and external locations before its optional learning catalog. Do not use workspace-local groups as Unity
Catalog owners; use account-level identities.

Instance-profile registration is opt-in. When enabled, group names in
`instance_profile_group_names` must exist in 04-workspace's `groups` map.
Policy IDs and warehouse IDs for jobs can be copied into tfvars after the
respective resources have been applied, then jobs can be added in a subsequent
apply. The root's defaults create no paid SQL warehouses or jobs.

Staging and production are still scaffolds and are not ready to apply.

## Account groups and workspace access

Module sources are organized under modules/aws and modules/databricks.
03-data-access calls modules/databricks/data-access, including the reusable
AWS IAM modules. Workspace creation remains isolated in account state.

The local development configuration keeps databricks-dev-admins as ADMIN and
adds databricks-dev-developer and databricks-dev-reader as USER. Admins manage
membership of the two new native account groups; both start empty. Developers
can use the existing compute policy and develop data in medallion schemas;
readers get SELECT on gold. Workspace assignment, membership management, compute
access, and Unity Catalog grants are distinct permissions.
See the [group and delegation guide](../../README.md#development-groups-and-delegation)
for the permission matrix, membership workflow, team-lead delegation, and apply
order (02-account → 03-data-access → 04-workspace). Readers still require access
to an approved existing SQL warehouse; this change creates no warehouse.

Configure `account_groups` in `02-account/terraform.tfvars` to create account
groups containing existing users and service principals and assign workspace
access. See the [account-groups module](../../modules/databricks/account-groups/README.md)
and phase-two tfvars example. Use numeric account SCIM IDs, not OAuth client
IDs. Groups default to USER; ADMIN grants workspace administration. Empty
`account_groups` creates nothing. Manage these account groups here rather than
creating workspace-local groups with the same names in `04-workspace`.

## Monthly Databricks budget

Phase two supports a workspace-scoped budget with an overridable 10 USD monthly
limit. Configure recipients in `02-account/terraform.tfvars` to enable it:

```hcl
monthly_budget_usd = 10
budget_alert_email_addresses = ["YOUR_EMAIL_ADDRESS"]
budget_alert_threshold_percentages = [50, 80, 100]
```

Replace the email placeholder. The default thresholds are 5, 8, and 10 USD;
empty recipients disable creation. See the
[account-budgets module](../../modules/databricks/account-budgets/README.md).
These are Databricks list-price alerts and do not stop workloads or cover AWS
infrastructure charges.

## AWS CloudWatch dashboard

Phase one creates the [AWS observability module](../../modules/aws/observability/README.md)
by default. Review its dashboard/alarm costs in your plan; disable it with
`enable_observability = false`. Add existing SNS topic ARNs to
`observability_alarm_action_arns` for notifications. Optional
`observability_s3_request_metrics = true` enables billable S3 request/transfer
metrics. EC2 widgets include running Databricks-tagged instances discovered in
this VPC; apply phase one after compute changes to update dashboard membership.

## Kinesis stream for Databricks compute

Set `kinesis_stream` in `01-infra/terraform.tfvars` to create an on-demand
stream. This attaches read-only consumer permissions to the existing Databricks
compute instance-profile role for that stream only. The VPC Kinesis interface
endpoint is already part of phase one. Apply phase one, then configure the
instance-profile registration and group access in phase four before assigning
the profile to a compute policy.

## Basic single-node compute policy

Phase four includes [compute-policy.tfvars.example](04-workspace/compute-policy.tfvars.example)
for a general-purpose `m5d.xlarge` single-node development policy. It fixes
zero workers, one driver instance, latest LTS runtime, dedicated access mode,
on-demand capacity, and auto-termination after 20 idle minutes. Each user can
have at most one active cluster under this policy. The limit is per user, not
a workspace-wide maximum. Confirm the instance type is offered in your workspace
before using it; the policy is not a guarantee of a 10 USD monthly spend.

The development `04-workspace/terraform.tfvars` now enables this policy by default;
`compute-policy.tfvars.example` is also available for reuse. Normal `terraform plan`
and `terraform apply` load the development tfvars automatically.

The example grants CAN_USE to the account group `databricks-dev-admins`, which
must already be assigned to this workspace. It creates no running compute.
Multi-node compute cannot autoscale to zero workers; single-node compute keeps
one billable driver running until termination. Workspace admins can also use
other policies, so this is not a global restriction on administrator activity.

From `04-workspace`, after configuring backend and account/state inputs:

```bash
terraform plan
terraform apply
```

For another deployment, pass `-var-file=compute-policy.tfvars.example` to use
only the reusable example. That file overrides the entire `cluster_policies`
map; merge existing policies into that map if this state already manages others. Select `dev-single-node-basic`
when creating compute in the workspace UI.

## Landing and managed-data storage

Phase one now creates two dedicated data buckets by default using names with
the environment, region, and AWS account ID. Run `terraform plan`, review, then
`terraform apply` in `01-infra`. Inspect them with
`terraform output data_storage_buckets`. Both also appear on the infrastructure
CloudWatch dashboard. No bucket-name tfvars are needed.

This step provisions S3 only. UC roles, credentials and external locations are created together in 03-data-access. The landing bucket will hold incoming
files exposed through external volumes; the managed bucket will back a catalog
with bronze, silver, and gold schemas. Neither bucket is the workspace root.


## Unity Catalog data access

S3 buckets remain in 01-infra. Configure and apply the
[03-data-access root](03-data-access/README.md) after workspace creation.
It assigns/creates the metastore before registering credentials and planned role
ARNs, creating dedicated IAM trust, waiting for propagation, and validating
external locations. No bootstrap flags or manual trust copying are required.
Optionally set catalog_name = "dev_analytics" for bronze/silver/gold schemas and
an ingestion.incoming volume. Its account groups must already exist in 02-account.

The old deployment was destroyed before this reorder. Live deployments elsewhere
need an explicit migration; do not simply change keys or duplicate ownership.

## Dedicated cluster log storage

Apply 01-infra → 02-account → 03-data-access → 04-workspace once each.
The operations bucket is created in 01, workspace/groups in 02, metastore and
volumes in 03, and policies in 04. Verify root 03's cluster_log_volume_path output
matches root 04's input. The local dev paths already match. No initial null-path
apply or second compute apply is needed for a fresh deployment.
See the [full logging guide](../../README.md#dedicated-cluster-log-storage).
## Hello-world compute init script

The source and upload are owned by modules/databricks/cluster-policies.
03-data-access creates only the managed init_scripts volume and its grants.
04-workspace enables `enable_hello_world_init_script` and supplies
`init_script_volume_path` to upload the bundled file and enforce its policy path.
Apply 03 before 04. The next fresh deployment needs no file import. See the
[init script guide](../../README.md#hello-world-init-script).

## Destroy

Stop workloads, then run terraform destroy from each root in order:
04-workspace → 03-data-access → 02-account → 01-infra. This removes files/policies
before volumes, preserves metastore access for UC cleanup, and deletes the
workspace before AWS resources. UC retention can delay external-location deletion.
Versioned S3 data buckets need all versions and delete markers emptied before
bucket deletion. Preserve the Terraform state bucket and its history.
