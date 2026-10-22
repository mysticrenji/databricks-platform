# Data storage

Creates two S3 buckets: landing for externally delivered files, and uc_managed
for Unity Catalog managed tables and volumes. Names include the supplied prefix
and the current AWS account ID. A globally conflicting name still needs a different
prefix. Changing the prefix replaces buckets; choose it before the first apply.

Both buckets block public access, disable ACLs, enable versioning and SSE-S3
encryption, require HTTPS, and keep force_destroy disabled. No lifecycle expiration
rules are configured: do not expire Unity Catalog managed table files through S3.
Stored object versions incur storage charges until explicitly removed.

Inputs: name (required, 2-39 lowercase letters/numbers/hyphens), tags (optional map).
Output: buckets, keyed by landing and uc_managed, with name, arn, and url.

Development 01-infra creates these buckets by default. Run terraform plan and
review before applying; terraform output data_storage_buckets shows their details.
The existing workspace root bucket remains separate.

This module creates storage only. It grants no producer or compute-role access.
UC IAM roles, credentials, external locations, and optional learning catalogs
are managed together in 03-data-access. See its README for the single-apply flow.
## Optional operations/log bucket

Set `enable_observability_bucket = true` to add an `observability` entry to
`buckets`. It generates `<name>-logs-<AWS account ID>`; override it with
`observability_bucket_name`. Default false keeps the existing two-bucket layout.
The existing landing/uc_managed keys and names are unchanged. The third bucket
uses the same public-access block, SSE-S3 encryption, versioning, TLS enforcement,
and force_destroy=false. No lifecycle expiration is added to UC managed data.
The data-access root owns the dedicated IAM role and Unity Catalog mapping.
