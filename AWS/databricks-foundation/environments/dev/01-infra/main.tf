locals {
  deployment_name = "databricks-${var.environment_name}-${var.workspace_key}"
}

# 1. Vpc
module "vpc" {
  source = "../../../modules/aws/vpc"

  name       = "${local.deployment_name}-vpc"
  cidr_block = var.vpc_cidr_block
}

# 2. Workspace subnets
module "workspace_subnets" {
  source = "../../../modules/aws/subnets"

  name              = "${local.deployment_name}-workspace"
  vpc_id            = module.vpc.vpc_id
  workspace_subnets = var.workspace_subnets
}

# 3. Egress
module "egress" {
  source = "../../../modules/aws/egress"

  name                              = local.deployment_name
  vpc_id                            = module.vpc.vpc_id
  nat_subnets                       = var.nat_subnets
  workspace_subnet_ids              = module.workspace_subnets.subnet_ids
  workspace_subnet_nat_gateway_keys = var.workspace_subnet_nat_gateway_keys
}

# 4. Workspace security group
module "workspace_security_group" {
  source = "../../../modules/aws/security-groups"

  name               = "${local.deployment_name}-workspace"
  vpc_id             = module.vpc.vpc_id
  enable_privatelink = var.enable_privatelink
  enable_fips        = var.enable_fips
}

# 5. Vpc endpoints
module "vpc_endpoints" {
  source = "../../../modules/aws/vpc-endpoints"

  name                        = local.deployment_name
  aws_region                  = var.aws_region
  vpc_id                      = module.vpc.vpc_id
  workspace_security_group_id = module.workspace_security_group.workspace_security_group_id
  endpoint_subnets            = var.endpoint_subnets
  workspace_route_table_ids   = module.egress.workspace_route_table_ids
}

# 6. Iam roles
module "iam_roles" {
  source = "../../../modules/aws/IAM-roles"

  name                  = local.deployment_name
  databricks_account_id = var.databricks_account_id
}

# 7. Kms
module "kms" {
  source = "../../../modules/aws/kms"

  enabled                              = var.enable_customer_managed_kms
  name                                 = local.deployment_name
  aws_region                           = var.aws_region
  aws_account_id                       = var.aws_account_id
  cross_account_role_name              = module.iam_roles.cross_account_role_name
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
}

# 8. Root storage
module "root_storage" {
  source = "../../../modules/aws/root-storage"

  name                                 = local.deployment_name
  bucket_name                          = var.root_storage_bucket_name
  databricks_account_id                = var.databricks_account_id
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
  aws_region                           = var.aws_region
  kms_key_arn                          = module.kms.key_arn
}

# 9. Optional Kinesis stream and least-privilege Databricks compute consumer access.
module "kinesis" {
  for_each = var.kinesis_stream == null ? {} : { stream = var.kinesis_stream }
  source   = "../../../modules/aws/kinesis"

  name                                 = each.value.name
  retention_period_hours               = each.value.retention_period_hours
  workspace_instance_profile_role_name = module.iam_roles.workspace_instance_profile_role_name
}

# 10. CloudWatch infrastructure dashboard and NAT alarms.
module "observability" {
  for_each                  = var.enable_observability ? { infra = true } : {}
  source                    = "../../../modules/aws/observability"
  name                      = "${local.deployment_name}-infra"
  aws_region                = var.aws_region
  vpc_id                    = module.vpc.vpc_id
  nat_gateway_ids           = module.egress.nat_gateway_ids
  bucket_names              = merge({ root = module.root_storage.bucket_name }, { for key, bucket in module.data_storage.buckets : key => bucket.name })
  ebs_volume_ids            = var.observability_ebs_volume_ids
  alarm_action_arns         = var.observability_alarm_action_arns
  enable_s3_request_metrics = var.observability_s3_request_metrics
}

# 11. Landing files and Unity Catalog managed-data storage.
module "data_storage" {
  source                      = "../../../modules/aws/data-storage"
  name                        = local.deployment_name
  enable_observability_bucket = var.enable_observability_bucket
  observability_bucket_name   = var.observability_bucket_name
}
