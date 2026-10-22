# Databricks workspace security group

Creates the security group used by Databricks classic compute in a
customer-managed AWS VPC. It creates no inbound rule from the internet.

The module permits all TCP and UDP traffic only when the source or destination
uses the same security group, as Databricks requires for internal cluster
traffic. It allows the Databricks-required TCP ports to `0.0.0.0/0` for outbound
traffic: `53`, `443`, `3306`, `5432`, `8443-8451`. The optional TCP `6666` and
`2443` rules are included only for classic PrivateLink and FIPS respectively.

```hcl
module "workspace_security_group" {
  source = "./modules/aws/security-groups"

  name   = "databricks-dev-workspace"
  vpc_id = module.vpc.vpc_id

  enable_privatelink = false
  enable_fips        = false
}
```

Use `workspace_security_group_id` when registering the network with Databricks.
Databricks permits one through five security groups per workspace and recommends
using a unique security group for each workspace.

The outbound CIDR rules provide required connectivity; they do not bypass the
network routes, NAT gateways, egress firewalls, or VPC endpoints configured
elsewhere. Add endpoint security-group rules in a dedicated endpoint component.

## Outputs

- `workspace_security_group_id`
- `workspace_security_group_arn`

## References

- [Databricks customer-managed VPC security group requirements](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc)
- [Terraform AWS security group rule resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule)
