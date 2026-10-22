# Storage credentials

Registers deterministic planned AWS IAM role ARNs through databricks.workspace.
Credentials belong to the workspace's Unity Catalog metastore and are isolated
to the current workspace. Validation stays enabled and force_destroy is false.

Input: credentials (map keyed by purpose with name and role_arn; default empty).
Outputs: names and trust (external_id and unity_catalog_iam_arn).
No bootstrap or trust_configured flags are required.

Used by modules/databricks/data-access: credentials register first, then their
trust details flow directly to IAM role creation in the same Terraform state.
See [03-data-access](../../../environments/dev/03-data-access/README.md).
