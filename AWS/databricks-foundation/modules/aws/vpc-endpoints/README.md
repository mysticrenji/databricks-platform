# Databricks AWS service VPC endpoints

Creates private connectivity from a Databricks customer-managed VPC to the AWS
services the workspace must reach: an S3 gateway endpoint plus STS and Kinesis
Streams interface endpoints. Private DNS is enabled for the interface endpoints.

The module creates dedicated endpoint subnets across at least two availability
zones and an endpoint security group. The security group accepts HTTPS only from
the workspace security group. This keeps endpoint access separate from the
workspace security group while meeting the required connectivity rule.

```hcl
module "vpc_endpoints" {
  source = "./modules/aws/vpc-endpoints"

  name                        = "databricks-dev-eu-central-1"
  aws_region                  = "eu-central-1"
  vpc_id                      = module.vpc.vpc_id
  workspace_security_group_id = module.workspace_security_group.workspace_security_group_id
  workspace_route_table_ids   = module.egress.workspace_route_table_ids

  endpoint_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.242.0/24"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.243.0/24"
    }
  }
}
```

The module accepts one shared workspace route table for single-NAT deployments
or multiple workspace route tables for per-AZ egress. Interface endpoint subnets
must still span at least two availability zones.

The S3 endpoint is attached to every workspace route table so in-region S3
traffic remains on the AWS network. STS and Kinesis endpoints create network
interfaces in the dedicated endpoint subnets. Each interface endpoint has an
hourly and data-processing charge.

This module deliberately leaves endpoint policies unrestricted. Restrictive S3
and endpoint policies must be designed together with the root storage bucket,
Databricks-required regional buckets, IAM roles, and any cross-region access.
Add those policies when building the storage and IAM components.

## Outputs

- `s3_gateway_endpoint_id`
- `sts_interface_endpoint_id`
- `kinesis_interface_endpoint_id`
- `endpoint_security_group_id`
- `endpoint_subnet_ids`

## References

- [Databricks customer-managed VPC requirements](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc)
- [Databricks classic PrivateLink guidance](https://docs.databricks.com/aws/en/security/network/classic/privatelink)
- [AWS interface VPC endpoint guidance](https://docs.aws.amazon.com/vpc/latest/privatelink/create-interface-endpoint.html)
