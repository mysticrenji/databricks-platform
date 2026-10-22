variable "name" {
  description = "CloudWatch dashboard name and alarm name prefix."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[A-Za-z0-9_-]{1,200}$", var.name))
    error_message = "name must be 1-200 letters, digits, underscores, or hyphens."
  }
}
variable "aws_region" {
  description = "AWS region of the monitored resources and dashboard widgets."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z]{2}(-gov)?-[a-z]+-[0-9]+$", var.aws_region))
    error_message = "aws_region must be an AWS region identifier."
  }
}
variable "vpc_id" {
  description = "VPC used to discover running Databricks-tagged EC2 instances."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a VPC ID."
  }
}
variable "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by stable subnet names."
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition     = alltrue([for id in values(var.nat_gateway_ids) : can(regex("^nat-[0-9a-f]+$", id))])
    error_message = "nat_gateway_ids must contain NAT gateway IDs."
  }
}
variable "bucket_names" {
  description = "S3 buckets keyed by stable logical names, including root storage and optional data buckets."
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition     = alltrue([for name in values(var.bucket_names) : length(trimspace(name)) > 0 && name == trimspace(name)])
    error_message = "Bucket names must be non-empty without surrounding whitespace."
  }
}
variable "ebs_volume_ids" {
  description = "Optional EBS volume IDs keyed by stable logical names for I/O widgets."
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition     = alltrue([for id in values(var.ebs_volume_ids) : can(regex("^vol-[0-9a-f]+$", id))])
    error_message = "ebs_volume_ids must contain EBS volume IDs."
  }
}
variable "enable_s3_request_metrics" {
  description = "Enable billable S3 request, latency, error, and transfer metrics for each bucket."
  type        = bool
  default     = false
  nullable    = false
}
variable "alarm_action_arns" {
  description = "Existing SNS topic ARNs to notify on alarm and recovery. Empty means alarms have no notifications."
  type        = set(string)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for arn in var.alarm_action_arns : can(regex("^arn:[^:]+:sns:[^:]+:[0-9]{12}:.+$", arn))])
    error_message = "alarm_action_arns must contain SNS topic ARNs."
  }
}
variable "tags" {
  description = "Tags for CloudWatch alarms."
  type        = map(string)
  default     = {}
  nullable    = false
}
