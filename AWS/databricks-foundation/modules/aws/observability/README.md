# Databricks AWS observability

Creates a CloudWatch dashboard and NAT gateway alarms using existing AWS
resources. Uses the root AWS provider; it does not create compute or storage.

```hcl
module "observability" {
  source = "./modules/aws/observability"
  name = "databricks-dev-infra"
  aws_region = var.aws_region
  vpc_id = module.vpc.vpc_id
  nat_gateway_ids = module.egress.nat_gateway_ids
  bucket_names = { root = module.root_storage.bucket_name }
  # Optional existing SNS topic, with subscriptions managed separately:
  # alarm_action_arns = ["arn:aws:sns:eu-central-1:123456789012:infra-alerts"]
}
```

## Coverage

- Running EC2 instances with `Vendor=Databricks` in the selected VPC: CPU,
  network bytes, and status failures. Discovery requires `ec2:DescribeInstances`
  and refreshes on Terraform plan/apply; apply to update dashboard membership
  after clusters start, stop, or scale. No EC2 widgets are created if discovery
  is empty. For multiple workspaces sharing a VPC, the view covers all matching
  instances. Serverless compute runs outside your AWS account and is not visible.
- NAT gateways: traffic bytes, packet drops, and port-allocation failures. Two
  alarms per gateway trigger after two consecutive five-minute error periods.
  Without SNS ARNs, alarms are visible in CloudWatch but send no notifications.
- S3: daily standard-storage bytes and all-storage-class object counts. Other
  storage classes are not included in the standard-storage bytes widget.
- Optional `ebs_volume_ids`: EBS read/write bytes. Supply current volume IDs;
  volumes of short-lived clusters change and are not automatically discovered.
- Optional `enable_s3_request_metrics`: creates a bucket metric configuration
  and graphs requests, errors, and uploaded/downloaded bytes. This is disabled
  by default because request metrics incur charges. Do not duplicate ownership
  of an existing bucket metric configuration named DatabricksObservability.

Memory, filesystem occupancy, and Spark metrics are not native EC2 metrics;
this module does not install agents or modify Databricks nodes. Use Databricks
compute metrics for those initially. Dashboards and alarms can incur AWS costs.

## Cost reporting

CloudWatch bytes and utilization are operational metrics, not an AWS bill.
Use AWS Cost Explorer first, activating tags such as Project, Environment,
Vendor, and ClusterId as cost allocation tags. Tag foundation resources and
configure custom tags on Databricks compute/pools; AWS provider default tags do
not automatically apply to instances created by Databricks.

For detailed compute, EBS, S3, NAT, endpoint, and transfer charges, use AWS Data
Exports CUR 2.0 to S3 and query it with Athena (or ingest it into Databricks).
Some shared network costs require an allocation rule and do not map directly to
one cluster. VPC Flow Logs are an optional later addition for traffic diagnosis;
byte counts are not a substitute for CUR pricing. Track serverless and DBU costs
with Databricks billing system tables. If Databricks is billed through AWS
Marketplace, avoid double-counting those charges when combining the reports.

## Validation

```bash
terraform init -backend=false
terraform test
terraform fmt -check -recursive .
```

## References

- [Databricks AWS resource tags](https://docs.databricks.com/aws/en/admin/account-settings/usage-detail-tags)
- [NAT gateway metrics](https://docs.aws.amazon.com/vpc/latest/userguide/metrics-dimensions-nat-gateway.html)
- [S3 metrics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-dimensions.html)
- [CUR 2.0 exports](https://docs.aws.amazon.com/cur/latest/userguide/creating-cur.html)
