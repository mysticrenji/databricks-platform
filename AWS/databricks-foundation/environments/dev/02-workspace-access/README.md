# Workspace feature access after provisioning

This workspace-only root runs after `02-account` has provisioned the workspace, account groups and USER/ADMIN assignments, and before dataset permission planning. It manages entitlements only through the workspace provider. It creates no identities, memberships, assignments, catalogs or compute. It does not require a metastore or datasets.

The runner supplies verified root 02 identity and group IDs as isolated inputs; this root reads no remote state. Use a separate backend key `databricks/dev/<workspace>/02-workspace-access.tfstate`, never the account or permissions state. Root 02 keeps group/assignment ownership and root 05 must not own these bootstrap entitlements. An existing entitlement owner requires reviewed migration before execution.

| Persona | Workspace | SQL | Unrestricted clusters | Instance pools |
| --- | --- | --- | --- | --- |
| Admins | true | true | true | true |
| Engineers | true | true | false | false |
| Analysts | false | true | false | false |
| ML | true | true | false | false |

Administrator capability flags preserve built-in capabilities; they do not create compute. Other memberships and default workspace groups can widen effective access. Membership remains externally managed.

Initialize using `terraform init -reconfigure -backend-config=backend.hcl` with reviewed backend inputs. Saved plans must be regenerated after source changes. Apply is gated by the provisioning workflow approvals and opt-in; development validation uses only `terraform init -backend=false` and mocked `terraform test`.

Teardown must remove this entitlement state before deleting root 02 groups/workspace. Never silently release or transfer ownership.
