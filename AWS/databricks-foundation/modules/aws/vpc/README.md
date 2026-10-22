# VPC

First network building block for a Databricks customer-managed VPC on AWS.
Creates one IPv4 VPC with shared tenancy, DNS resolution, DNS hostnames, and tags.
The caller configures the AWS provider, region, credentials, and Terraform state.

## Usage

```hcl
module "vpc" {
  source = "./modules/aws/vpc"

  name       = "databricks-dev-eu-central-1-vpc"
  cidr_block = "10.20.0.0/16"

  tags = {
    Environment = "dev"
    Project     = "databricks"
    ManagedBy   = "Terraform"
  }
}
```

Requirements: Terraform >= 1.7, < 2.0; HashiCorp AWS provider >= 6.0, < 7.0.
Configure authentication in the calling root using your AWS credential chain
(for example, AWS SSO locally or an assumed role in CI).

| Input | Required | Description |
| --- | --- | --- |
| `name` | Yes | Non-empty Name tag; overrides `tags["Name"]`. |
| `cidr_block` | Yes | Canonical private RFC 1918 IPv4 CIDR, /16 through /25. |
| `tags` | No | Additional tags; defaults to `{}`. |

Outputs: `vpc_id`, `vpc_arn`, and `cidr_block`.

## Address planning

Choose an allocated CIDR that does not overlap connected VPCs, on-premises
networks, or planned environments. `10.20.0.0/16` is an illustrative value;
the module cannot detect overlaps outside this configuration.

AWS permits VPCs from /16 through /28. This module deliberately restricts
the range to /16 through /25 and RFC 1918 private space for Databricks.
Databricks requires at least two private subnets in different availability
zones, each /17 through /26. A /25 can fit only two /26 subnets, leaving no
space for NAT gateway or endpoint subnets. Use a larger allocation for those
components and future growth. Databricks consumes two IP addresses per compute
node, and AWS reserves five addresses per subnet.

## Scope and next components

This VPC alone is not ready to host a workspace. Build the remaining components
in this order:

1. Subnets across at least two availability zones, sized for compute and any NAT/endpoints.
2. Egress connectivity and route tables (NAT gateways and an internet gateway, or approved alternative).
3. Dedicated Databricks security groups and any required VPC endpoints.
4. VPC Flow Logs and their logging destination/IAM configuration before production use.
5. Databricks network registration and workspace provisioning.

AWS automatically creates a default security group, route table, and network ACL
with each VPC. This module leaves those defaults unmanaged. Future subnet modules
should use explicit route table associations and dedicated security groups;
review the default security group before production use. Keep network ACLs
compatible with Databricks requirements.

## Run the example

From `infra/examples/vpc`:

```sh
cp terraform.tfvars.example terraform.tfvars
# Edit the region and CIDR, and authenticate to your intended AWS account.
terraform init
terraform validate
terraform plan
```

Review the plan before applying. The example uses local state for learning;
configure a shared backend with locking and restricted access before team use.
Commit the example root's generated `.terraform.lock.hcl` to pin provider selection.

Run offline module tests after provider installation:

```sh
terraform -chdir=modules/aws/vpc init -backend=false
terraform -chdir=modules/aws/vpc test
```

## References

- [Databricks customer-managed VPC requirements](https://docs.databricks.com/aws/en/security/network/classic/customer-managed-vpc)
- [AWS VPC CIDR blocks](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-cidr-blocks.html)
- [Terraform aws_vpc resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc)
