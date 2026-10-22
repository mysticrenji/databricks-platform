# Unity Catalog permissions on existing objects

Manages only `databricks_grant`, authoritative for one principal/object pair.
Other principals are preserved. Supply the workspace provider alias and a map
of catalog/schema/table scopes, principals and explicit reader/writer privileges.
Union all workload contributions to each pair before calling this module.

This module creates no data objects, storage, memberships, compute, bindings or
metastore assignments. Missing objects fail the runner's SDK preflight. Never
overlap this module with another `databricks_grant` for the same pair or an
authoritative `databricks_grants` for the same object. Existing grant adoption
requires a reviewed Terraform import and release by the previous owner.

Run `terraform init -backend=false` and `terraform test` for mocked verification.
