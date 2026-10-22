terraform {
  required_version = ">= 1.7.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "databricks"
      Environment = "dev"
      ManagedBy   = "Terraform"
    }
  }
}

module "vpc" {
  source = "../../../modules/aws/vpc"

  name       = "databricks-dev-${var.aws_region}-vpc"
  cidr_block = var.vpc_cidr_block
}

module "workspace_subnets" {
  source = "../../../modules/aws/subnets"

  name              = "databricks-dev-${var.aws_region}-workspace"
  vpc_id            = module.vpc.vpc_id
  workspace_subnets = var.workspace_subnets
}

module "egress" {
  source = "../../../modules/aws/egress"

  name                              = "databricks-dev-${var.aws_region}"
  vpc_id                            = module.vpc.vpc_id
  nat_subnets                       = var.nat_subnets
  workspace_subnet_ids              = module.workspace_subnets.subnet_ids
  workspace_subnet_nat_gateway_keys = var.workspace_subnet_nat_gateway_keys
}

module "workspace_security_group" {
  source = "../../../modules/aws/security-groups"

  name               = "databricks-dev-${var.aws_region}-workspace"
  vpc_id             = module.vpc.vpc_id
  enable_privatelink = var.enable_privatelink
  enable_fips        = var.enable_fips
}

module "vpc_endpoints" {
  source = "../../../modules/aws/vpc-endpoints"

  name                        = "databricks-dev-${var.aws_region}"
  aws_region                  = var.aws_region
  vpc_id                      = module.vpc.vpc_id
  workspace_security_group_id = module.workspace_security_group.workspace_security_group_id
  endpoint_subnets            = var.endpoint_subnets
  workspace_route_table_ids   = module.egress.workspace_route_table_ids
}

module "iam_roles" {
  source = "../../../modules/aws/IAM-roles"

  name                  = "databricks-dev-${var.aws_region}"
  databricks_account_id = var.databricks_account_id
}

module "kms" {
  source = "../../../modules/aws/kms"

  enabled                              = var.enable_customer_managed_kms
  name                                 = "databricks-dev-${var.aws_region}"
  aws_region                           = var.aws_region
  aws_account_id                       = var.aws_account_id
  cross_account_role_name              = module.iam_roles.cross_account_role_name
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
}

module "root_storage" {
  source = "../../../modules/aws/root-storage"

  name                                 = "databricks-dev-${var.aws_region}"
  bucket_name                          = var.root_storage_bucket_name
  databricks_account_id                = var.databricks_account_id
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
  aws_region                           = var.aws_region
  kms_key_arn                          = module.kms.key_arn
}

variable "aws_region" {
  description = "AWS region for the VPC and future Databricks workspace."
  type        = string
  nullable    = false
}

variable "databricks_account_id" {
  description = "Databricks account ID used as the cross-account role external ID."
  type        = string
  sensitive   = true
  nullable    = false
}

variable "enable_customer_managed_kms" {
  description = "Whether to create a customer-managed KMS key and use SSE-KMS for root storage."
  type        = bool
  default     = false
  nullable    = false
}

variable "aws_account_id" {
  description = "AWS account ID that owns the KMS key. Required only when enable_customer_managed_kms is true."
  type        = string
  default     = null
  nullable    = true
}

variable "root_storage_bucket_name" {
  description = "Globally unique S3 bucket name for Databricks workspace root storage."
  type        = string
  nullable    = false
}

variable "vpc_cidr_block" {
  description = "Unused private IPv4 CIDR allocated for this environment."
  type        = string
  nullable    = false
}

variable "workspace_subnets" {
  description = "Databricks workspace subnets in separate availability zones."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))
  nullable = false
}

variable "nat_subnets" {
  description = "Public NAT gateway subnets in the same availability zones as workspace subnets."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))
  nullable = false
}

variable "workspace_subnet_nat_gateway_keys" {
  description = "Maps each workspace subnet key to its same-AZ NAT subnet key."
  type        = map(string)
  nullable    = false
}

variable "enable_privatelink" {
  description = "Whether the workspace uses classic PrivateLink."
  type        = bool
  default     = false
  nullable    = false
}

variable "enable_fips" {
  description = "Whether the workspace uses the FIPS compliance security profile."
  type        = bool
  default     = false
  nullable    = false
}

variable "endpoint_subnets" {
  description = "Dedicated private subnets for STS and Kinesis endpoint network interfaces."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))
  nullable = false
}

output "vpc_id" {
  description = "Created VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR for the subnet component."
  value       = module.vpc.cidr_block
}

output "workspace_subnet_ids" {
  description = "Subnet IDs for the Databricks network configuration."
  value       = module.workspace_subnets.subnet_ids_list
}

output "nat_gateway_public_ips" {
  description = "Public egress IPs for allowlisting with external systems."
  value       = module.egress.nat_gateway_public_ips
}

output "workspace_security_group_id" {
  description = "Security group ID for Databricks network registration."
  value       = module.workspace_security_group.workspace_security_group_id
}

output "vpc_endpoint_ids" {
  description = "AWS service endpoint IDs for the Databricks VPC."
  value = {
    s3      = module.vpc_endpoints.s3_gateway_endpoint_id
    sts     = module.vpc_endpoints.sts_interface_endpoint_id
    kinesis = module.vpc_endpoints.kinesis_interface_endpoint_id
  }
}

output "databricks_cross_account_role_arn" {
  description = "Role ARN for the future Databricks credential configuration."
  value       = module.iam_roles.cross_account_role_arn
}

output "workspace_instance_profile_arn" {
  description = "EC2 instance profile ARN for Databricks compute."
  value       = module.iam_roles.workspace_instance_profile_arn
}

output "root_storage_bucket_name" {
  description = "Databricks workspace root storage bucket."
  value       = module.root_storage.bucket_name
}

output "root_storage_kms_key_arn" {
  description = "Customer-managed KMS key ARN when enabled; otherwise null."
  value       = module.kms.key_arn
}
