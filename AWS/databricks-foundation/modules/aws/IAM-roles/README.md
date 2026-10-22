# Databricks workspace IAM roles

Creates the two AWS identities used by the initial Databricks workspace setup:

- A cross-account role trusted by the Databricks control plane. Its trust policy
  requires your Databricks account ID as the external ID.
- An EC2 role and instance profile for workspace compute. It has no data-access
  permissions until the root storage module attaches a least-privilege S3 policy.

The cross-account policy implements Databricks' published baseline permissions
for a customer-managed VPC. It is separate from the instance-profile role because
the roles serve different principals and purposes.

```hcl
module "iam_roles" {
  source = "./modules/aws/IAM-roles"

  name                  = "databricks-dev-eu-central-1"
  databricks_account_id = var.databricks_account_id

  # For AWS commercial regions, these defaults are correct.
  databricks_control_plane_account_id = "414351767826"
  aws_partition                       = "aws"
}
```

For AWS GovCloud, set `aws_partition` and `databricks_control_plane_account_id`
to the values documented by Databricks for your specific partition. The module
does not guess the Databricks account ID: retrieve it from the Databricks account
console and provide it as `databricks_account_id`.

The baseline cross-account policy includes permissions that Databricks needs to
create and manage workspace compute in a customer-managed VPC. It uses `Resource
= "*"` for EC2 APIs because AWS does not support resource-level controls for
many required describe, launch, and Spot APIs. Add an organization-approved
permissions boundary through `permissions_boundary_arn`; apply additional
resource restrictions only after validating them against the Databricks custom
restrictions guidance.

The cross-account role may pass only this module's compute instance-profile role
to EC2. Databricks needs that permission to verify and use the profile during
workspace registration; it cannot pass any other role or pass this role to a
different AWS service.

## Outputs

- `cross_account_role_arn`: use for the Databricks credential configuration.
- `workspace_instance_profile_arn`: use to register an instance profile later.
- `workspace_instance_profile_role_arn`: pass to the root storage module.

## References

- [Databricks cross-account IAM role permissions](https://docs.databricks.com/aws/en/admin/cloud-configurations/aws/permissions)
- [Create a workspace with manual AWS configurations](https://docs.databricks.com/aws/en/admin/workspace/create-uc-workspace)
