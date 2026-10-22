# Databricks VPC egress

Creates highly available public NAT infrastructure for Databricks workspace
subnets: an internet gateway, one public NAT subnet and public NAT gateway per
availability zone, and explicit public and private route tables.

Each workspace subnet is associated with a private route table whose default
route points to its selected NAT gateway. Each NAT subnet uses a public route
table whose default route points to the internet gateway. Workspace subnets do
not receive public IP addresses and never have a route directly to the internet
gateway.

```hcl
module "egress" {
  source = "./modules/aws/egress"

  name   = "databricks-dev"
  vpc_id = module.vpc.vpc_id

  nat_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.240.0/24"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.241.0/24"
    }
  }

  workspace_subnet_ids = module.workspace_subnets.subnet_ids
  workspace_subnet_nat_gateway_keys = {
    az1 = "az1"
    az2 = "az2"
  }
}
```

For high availability, map each workspace subnet to a NAT gateway in the same
availability zone. This avoids cross-AZ data charges and an availability-zone
outage removing egress for another zone. A single NAT subnet may instead serve
all workspace subnets where lower development cost is more important than
zonal egress resilience. Keep the map keys stable after deployment because
they are Terraform resource addresses.

The module creates public IPv4 NAT gateways and therefore incurs NAT gateway
and Elastic IP charges. Use the `nat_gateway_public_ips` output when external
systems require an egress allowlist.

This module does not create VPC endpoints, egress firewalls, network ACLs, or
security groups. Add endpoints for AWS services and a firewall/proxy when your
security requirements require controlled egress.

## Outputs

- `internet_gateway_id`
- `nat_gateway_ids`
- `nat_gateway_public_ips`
- `nat_subnet_ids`
- `workspace_route_table_ids`

## References

- [Databricks customer-managed VPC requirements](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc)
- [AWS NAT gateway basics](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-basics.html)
