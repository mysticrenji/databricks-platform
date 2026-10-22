# Unity Catalog storage roles

Creates a bucket-scoped IAM role for each landing/uc_managed bucket, with S3
list/read/write/delete and restricted self-assumption. Trust is supplied directly
from the storage-credentials module in the same 03-data-access state.
No compute instance-profile or workspace deployment role is modified.

Inputs: name, buckets (map with arn), trust (map with external_id and
unity_catalog_iam_arn), tags (optional map). Output: roles (arn and trust_configured).
Empty trust creates self-only roles; the integration always supplies generated
credential trust. Buckets use SSE-S3; CMK encryption would need KMS permissions.

See [03-data-access](../../../environments/dev/03-data-access/README.md).
## Operations storage

The bucket map also accepts the optional `observability` key. It receives its
own bucket-scoped IAM role and credential-specific trust, independent of landing
and analytics storage. Use the data-access composition to pass generated trust
directly; no cross-state bootstrap or new instance-profile access is required.
