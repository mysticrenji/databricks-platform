# Workspace feature entitlements

Sets explicit feature entitlements on verified existing account groups through `databricks.workspace`. Creates no groups, assignments, memberships, data objects or compute. Inputs default to an empty map. Each group ID has one stable persona key; callers must verify workspace assignment and identity before planning.

USER groups require workspace or SQL access and cannot create unrestricted clusters or instance pools. ADMIN inputs retain all four capabilities; setting false is not an admin restriction mechanism. Permissions inherited from other groups or workspace defaults can widen effective access.

The dev/demo matrix enables workspace and SQL for engineers/ML, SQL only for analysts, and preserves administrator capabilities. Account group lifecycle and workspace assignments remain in root `02-account`; dataset grants remain separate.

Run `terraform init -backend=false` and `terraform test` for credential-free mocked validation. Never use this module to adopt entitlements already owned by another Terraform root without a reviewed ownership migration.
