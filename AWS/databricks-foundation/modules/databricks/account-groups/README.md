# Databricks account groups

Creates account-level groups, adds existing account users or service principals,
and assigns each group to one identity-federated workspace. Use the
`databricks.accounts` provider with an account administrator identity.

```hcl
module "account_groups" {
  source = "./modules/databricks/account-groups"
  providers = { databricks.accounts = databricks.accounts }
  workspace_id = module.workspace.workspace_id
  groups = {
    "databricks-dev-admins" = {
      workspace_permission = "ADMIN"
      member_ids = {
        me = "REPLACE_WITH_USER_SCIM_ID"
        terraform = "REPLACE_WITH_SERVICE_PRINCIPAL_SCIM_ID"
      }
    }
  }
}
```

Replace the placeholders with numeric account SCIM IDs. The service principal's
SCIM ID is different from its OAuth application/client ID. Find existing IDs
using account-level `databricks_user` or `databricks_service_principal` data
sources, or the account SCIM API. This module does not create users or service
principals and does not manage their secrets.

`groups` defaults to empty. Each group's `member_ids` defaults to empty and
`workspace_permission` defaults to `USER`. Use stable member keys so computed
IDs can be passed from other resources. `ADMIN` grants workspace administration;
it does not grant the account admin role. Manage compute entitlements, job
permissions, and Unity Catalog grants separately in the workspace state.

This module owns each declared group, membership pair, and workspace assignment.
Import existing resources before managing them; do not manage the same membership
or assignment in another Terraform state. For IdP-managed groups, keep membership
in the IdP and use a separate assignment flow for existing groups. Removing a
membership or assignment revokes that access path; deleting a managed group can
affect every workspace using it. Account groups may take a few minutes to
propagate after membership updates.

Outputs: `group_ids` and `workspace_assignment_ids`, both keyed by group name.

## Delegating membership

Set `databricks_account_id` and a group's optional `manager_group_names` to
delegate native account-group management to other groups declared in this module:

```hcl
groups = {
  "databricks-dev-admins" = { workspace_permission = "ADMIN" }
  "databricks-dev-developer" = {
    workspace_permission = "USER"
    manager_group_names  = ["databricks-dev-admins"]
  }
}
```

This grants `roles/group.manager` on the developer group, not account-wide
administration. Managers can manage membership and other group-management
operations, including deleting the group; select trusted managers. The rule set
is authoritative. Include all intended managers, import existing managed rule
sets before taking ownership, and do not edit their roles independently.
An empty manager list creates no rule-set resource and leaves roles unmanaged.

Terraform owns only membership pairs explicitly listed in `member_ids`. Keep
that map empty for delegated developer/reader membership; managers can add
members without a Terraform run. Do not manually change Terraform-owned pairs.
For IdP-synchronized groups, delegate membership in the IdP instead.
Workspace admins with Manage on a group can use Settings → Identity and access
→ Groups. Managers without workspace admin access use the Account Groups API.

## Validation

```bash
terraform init -backend=false
terraform test
terraform fmt -check -recursive .
```

## References

- [Account group management](https://docs.databricks.com/aws/en/admin/users-groups/manage-groups)
- [Group membership](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/group_member)
- [Workspace assignments](https://registry.terraform.io/providers/databricks/databricks/latest/docs/resources/mws_permission_assignment)
