# Databricks workspace subnets

Creates private IPv4 subnets for a Databricks customer-managed VPC. The module
requires at least two subnets in distinct availability zones and accepts only
the `/17` through `/26` netmask range required by Databricks.

The module creates only workspace subnets. It does not create NAT, endpoint, or
route-table resources; those are separate network concerns.

```hcl
module "workspace_subnets" {
  source = "./modules/aws/subnets"

  name   = "databricks-dev-workspace"
  vpc_id = module.vpc.vpc_id

  workspace_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.0.0/20"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.16.0/20"
    }
  }
}
```

The `workspace_subnets` map keys must remain stable after deployment because
Terraform uses them as resource addresses. `subnet_ids_list` is sorted by those
keys and is suitable for the later Databricks network configuration.

Databricks uses two IP addresses per node, while AWS reserves five addresses in
each subnet. Plan space from expected concurrency and leave separate CIDR ranges
for NAT gateways and VPC endpoints. Subnet CIDRs must be inside the selected
VPC CIDR; AWS enforces this when the subnet is created.

Before registering the VPC with Databricks, associate every workspace subnet
with a route table that sends `0.0.0.0/0` to a NAT gateway or your approved
egress appliance. Do not attach an internet gateway directly to workspace
subnets.

## Outputs

- `subnet_ids`: IDs keyed by logical name.
- `subnet_ids_list`: IDs in stable logical-name order.
- `subnet_cidr_blocks`: CIDRs keyed by logical name.
- `availability_zones`: Availability zones keyed by logical name.

## References

- [Databricks customer-managed VPC requirements](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc)
- [Terraform aws_subnet resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet)
