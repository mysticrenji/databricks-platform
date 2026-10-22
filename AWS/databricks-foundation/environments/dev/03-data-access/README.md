# Development data access

Run third, after 01-infra and 02-account, before 04-workspace.
This root reads AWS bucket details from infra state and the workspace URL/ID
from account state. It owns regional metastore creation/assignment and calls
`modules/databricks/data-access` for dedicated UC IAM roles, storage credentials,
external locations, catalogs, schemas, and volumes. Buckets remain in 01-infra.

## Configure and apply

1. Copy backend.hcl.example and terraform.tfvars.example to their local filenames.
   Use your existing state bucket and its region. The example key is
   `databricks/dev/shared/03-data-access.tfstate`; local dev uses the existing
   `databricks-foundation/dev/` prefix. Match downstream remote-state keys.
2. Set databricks_account_id. Set existing_metastore_id to reuse the regional
   metastore, or explicitly enable create_metastore if a new one is needed.
   With both unset, the workspace must already have a suitable assignment.
3. Set catalog_name = "dev_analytics" to create bronze/silver/gold schemas and
   the external ingestion.incoming volume. Null creates storage access only.
4. Configure grants using the account groups created in 02-account. Account
   identities must exist before this root; do not depend on local identities in 04.
5. Authenticate AWS and Databricks using profiles/OAuth M2M or workload federation.
   AWS permissions must cover IAM roles/policies. The account provider requires
   metastore-assignment permissions; the workspace identity requires the relevant
   CREATE STORAGE CREDENTIAL, CREATE EXTERNAL LOCATION, CREATE CATALOG, and grant
   management privileges. Workspace ADMIN alone does not grant these UC privileges.
6. Run:

   ```bash
   terraform init -reconfigure -backend-config=backend.hcl
   terraform plan
   terraform apply
   terraform output
   ```

Metastore assignment precedes UC resources. Credentials return generated trust
details to the IAM role module in the same state; IAM propagation precedes
external-location validation. No bootstrap flags or manual external IDs are needed.
No running compute is created. Optional generic external_locations/catalogs maps
are also owned here; never duplicate data_access objects in those maps.

## Data and operations permissions

Catalog, schema, and volume grant maps are authoritative per object. Include all
intended principals; empty maps leave grants unmanaged. Local dev grants admins
ALL_PRIVILEGES plus MANAGE, developers medallion development access and incoming
read/write, and readers SELECT only on gold. See the
[group guide](../../../README.md#development-groups-and-delegation).

Dev also enables dev_operations.observability.cluster_logs and the separate
init_scripts managed volume. Developers have log read/write and script read;
readers receive no operations grants. Parent catalog/schema usage is required.
The shared log volume permits developers to read/write each other's logs; isolate
teams with separate volumes when needed. Script source/upload stays in cluster-policies.

Before applying 04-workspace, compare cluster_log_volume_path and
init_scripts_volume_path outputs with its configured log/script paths.

## State ownership and teardown

This layout was introduced after the old deployment states were verified empty.
No live state migration was performed. Other live deployments need an explicit
migration; changing the key alone creates a different state, not an ownership move.
See [initialization guidance](../../../README.md#initialization-after-the-reorder).

Destroy 04-workspace first, then this root, then 02-account and 01-infra.
Keep the metastore assignment and UC role access until dependent data objects are
removed. UC managed-data retention can delay external-location deletion. A reused
metastore remains shared and is not destroyed by this root.
