# Workspace access

Create account-level groups through the existing account-groups module or look
up explicitly registered external groups. Assign USER/ADMIN access to one
existing workspace and manage its group entitlements through the workspace
provider. External names must resolve to their reviewed SCIM IDs. No users,
memberships, catalogs, schemas, tables, or compute are created.

Pass `databricks.accounts` and `databricks.workspace` aliases and a `groups` map
matching variables.tf. Only the group creator owns group lifecycle; no name-based
automatic adoption is supported by the Python runner. Run the mocked tests with
`terraform init -backend=false` and `terraform test`. The permissions CI runner
rejects group/assignment deletions and ADMIN downgrades; retirement is separate.
