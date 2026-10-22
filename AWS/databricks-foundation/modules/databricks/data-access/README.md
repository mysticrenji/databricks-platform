# Unity Catalog data access

Located at `modules/databricks/data-access` and called by `03-data-access`.
The repository uses one module directory: `modules/aws` holds reusable AWS resources
and `modules/databricks` holds Databricks configuration and data-access composition.
AWS IAM roles remain implemented in the reusable infra module called here.

The development root was reordered to run before compute configuration after
the retired deployment's states were verified empty. The reusable source remains
under modules/databricks. Metastore setup belongs to the calling root, not this
module. See the development root for backend and initialization instructions.
Other live deployments need a reviewed state migration before adopting new roots.

Composes AWS and Databricks resources in one Terraform state, following the
[Databricks AWS UC example](https://github.com/databricks-solutions/technical-services-solutions/blob/main/workspace-setup/terraform-examples/aws/aws-byovpc-uc/tf/unity_catalog.tf).

Accepts existing S3 buckets; never creates or replaces buckets.
Registers storage credentials with deterministic planned IAM role ARNs, then
uses their generated external IDs and principal ARNs to create dedicated
bucket-scoped IAM roles. Waits 60 seconds for IAM propagation before creating
validated external locations. No manual trust copying or validation bypass.

Inputs: name (required prefix), buckets (required map of arn/url with landing
and uc_managed keys), catalog_name (optional, defaults null).
Providers: aws, databricks.workspace, and time; caller owns configuration.

Outputs: role_arns, credential_names, external_location_ids, catalog_ids.

Locations use /landing and /managed respectively. If catalog_name is supplied,
creates a managed catalog under /managed/<catalog_name> with bronze, silver,
gold and ingestion schemas, plus an external ingestion.incoming volume under
the landing bucket's /landing/incoming subpath. No group grants are added by default.
Optional `catalog_grants` passes an authoritative principal-to-privileges map to
the catalog module. Include all intended explicit catalog grants; do not manage
the same catalog grants in another resource. Applying grants requires the catalog
owner or an identity authorized to manage its grants.

`schema_grants` maps bronze/silver/gold/ingestion to principal-to-privileges maps.
`incoming_volume_grants` applies to ingestion.incoming. Both default to empty;
non-empty maps are authoritative on the respective schema or volume. Catalog
usage alone does not grant schema, table, or volume access. Scope reader SELECT
to gold rather than the catalog to avoid granting bronze/silver data access.
Credentials are isolated to the current workspace. Bucket roles trust only the
returned UC principal with its credential external ID, and themselves.

Requires a workspace already assigned to a Unity Catalog metastore, AWS
IAM administration, and UC privileges to create credentials/locations and,
if requested, catalogs. Actual cloud behavior still requires an authenticated
plan/apply; mocked tests verify Terraform's dependency graph and configuration.
IAM can propagate more slowly than the initial wait; retry an apply if needed.

See the [development root](../../../environments/dev/03-data-access/README.md).
## Dedicated operations storage

The bucket map accepts an optional `observability` bucket from infra.
Set the optional `observability` object to create a separate operations catalog
with a managed log volume. Its required `catalog_name` and optional
`schema_name` (observability), `volume_name` (cluster_logs),
`catalog_grants`, `schema_grants`, and `volume_grants` are configurable.
Defaults create no operations catalog. Enabling the object requires the bucket,
and its catalog name must differ from the analytics catalog.

The composition registers a separate storage credential, bucket-scoped IAM role,
and external location for the new bucket. The operations catalog's managed root
is `s3://<logs-bucket>/managed/<operations-catalog>`. UC chooses the physical
managed-volume directories. The output `cluster_log_volume_path` is the
Databricks path used by compute policies; `catalog_ids` includes both catalogs.
No Spark cluster, log parsing job, audit-log export, or CloudWatch log shipping
is created. The existing infrastructure dashboard includes the bucket's storage
metrics when infra passes it through.
## Optional init-script storage

Set `enable_init_scripts_volume = true` with `observability` configured to add
an init_scripts managed volume in the operations schema. `init_script_readers`
receives READ_VOLUME only; configure parent usage through observability grants.
This module owns storage and grants, not executable files. The
`init_scripts_volume_path` output identifies the existing destination volume.
The cluster-policies module owns the hello-world script and its upload.

The retired deployment needs no upload import. Historical live deployments may
have the file in data-access state; release its ownership without deleting it
and import it into the compute-policy owner only as part of an explicitly reviewed
migration. Never manage the file in both states. The historical removed block is
retained for compatibility; it does not perform a cross-state import.
