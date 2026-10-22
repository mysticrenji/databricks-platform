output "vpc_id" {
  description = "Created VPC ID."
  value       = module.vpc.vpc_id
}

output "data_storage_buckets" {
  description = "Landing, analytics managed-data, and optional observability bucket names, ARNs, and URLs."
  value       = module.data_storage.buckets
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

output "kinesis_stream" {
  description = "Configured Kinesis stream details; null when kinesis_stream is not configured."
  value = try({
    arn  = module.kinesis["stream"].stream_arn
    name = module.kinesis["stream"].stream_name
  }, null)
}

output "deployment_environment" {
  value = var.environment_name
}

output "deployment_workspace" {
  value = var.workspace_key
}

output "aws_region" {
  description = "Aws region."
  value       = var.aws_region
}

output "workspace_instance_profile_role_arn" {
  description = "Workspace instance profile role arn."
  value       = module.iam_roles.workspace_instance_profile_role_arn
}

output "observability_dashboard_arns" {
  description = "CloudWatch dashboard ARNs; empty when observability is disabled."
  value       = { for key, monitoring in module.observability : key => monitoring.dashboard_arn }
}
