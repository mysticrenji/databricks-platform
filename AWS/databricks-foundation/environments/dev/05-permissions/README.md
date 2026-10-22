# Existing workspace permissions

Dedicated root for UC grants on existing catalogs/schemas/tables. The four demo
bootstrap groups use `lifecycle: terraform`: root 02 creates them and assigns
workspace access; this root only looks up their verified IDs and manages data
grants. Bootstrap persona entitlements remain deferred. Separately adopted
create/external groups retain the workspace-access module contract.
It does not call roots 01-04 or create
any data objects or compute. Uses `databricks/dev/demo/05-permissions.tfstate`.
Run only through `tools/databricks-access/terraform_permissions.py`, which binds
target identity, checks legacy ownership and object existence, and saves plans.
Plan/apply workflow: `.github/workflows/databricks-permissions.yml`.
Module aliases are explicit; credentials are environment-provided OAuth M2M.
