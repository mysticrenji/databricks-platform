terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  backend "s3" {}
}
# VPC -> subnets -> egress -> security groups -> endpoints -> IAM -> KMS -> root storage.
