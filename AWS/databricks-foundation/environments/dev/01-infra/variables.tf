variable "environment_name" {
  description = "Deployment environment used in resource names and tags."
  type        = string
  default     = "dev"
  validation {
    condition     = contains(["dev", "staging", "production"], var.environment_name)
    error_message = "environment_name must be dev, staging, or production."
  }
}

variable "workspace_key" {
  description = "Stable workspace identifier within the deployment environment."
  type        = string
  default     = "shared"
  validation {
    condition     = length(var.workspace_key) <= 16 && can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.workspace_key))
    error_message = "workspace_key must be a lowercase slug of at most 16 characters."
  }
}

variable "aws_region" {
  description = "AWS region for the VPC and future Databricks workspace."
  type        = string
  nullable    = false
}

variable "enable_observability_bucket" {
  description = "Create a dedicated S3 bucket for Unity Catalog managed cluster logs and operational data."
  type        = bool
  default     = false
  nullable    = false
}

variable "observability_bucket_name" {
  description = "Optional logs bucket name; null generates an environment/region/account-specific name."
  type        = string
  default     = null
  nullable    = true
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
  description = "Public NAT gateway subnets. Use one per workspace availability zone for resilient egress, or one shared subnet for lower-cost development egress."
  type = map(object({
    availability_zone = string
    cidr_block        = string
  }))
  nullable = false
}

variable "workspace_subnet_nat_gateway_keys" {
  description = "Maps each workspace subnet key to the NAT subnet key that provides egress."
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

variable "kinesis_stream" {
  description = "Optional Kinesis Data Stream for Databricks compute to consume. Null creates no stream."
  type = object({
    name                   = string
    retention_period_hours = optional(number, 24)
  })
  default  = null
  nullable = true
}

variable "enable_observability" {
  description = "Create the AWS infrastructure CloudWatch dashboard and NAT alarms."
  type        = bool
  default     = true
  nullable    = false
}
variable "observability_alarm_action_arns" {
  description = "Existing SNS topic ARNs for infrastructure alarm notifications."
  type        = set(string)
  default     = []
  nullable    = false
}
variable "observability_s3_request_metrics" {
  description = "Enable billable S3 request and transfer metrics."
  type        = bool
  default     = false
  nullable    = false
}
variable "observability_ebs_volume_ids" {
  description = "Optional current EBS volume IDs keyed by logical name for dashboard I/O widgets."
  type        = map(string)
  default     = {}
  nullable    = false
}
