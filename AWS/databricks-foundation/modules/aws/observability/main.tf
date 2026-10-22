data "aws_instances" "databricks" {
  instance_state_names = ["running"]
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  instance_tags = { Vendor = "Databricks" }
}

resource "aws_s3_bucket_metric" "requests" {
  for_each = var.enable_s3_request_metrics ? var.bucket_names : {}
  bucket   = each.value
  name     = "DatabricksObservability"
}

locals {
  widget_definitions = concat(
    [{ type = "text", properties = { markdown = "# Databricks AWS infrastructure\nEC2 discovery refreshes on Terraform apply. This dashboard reports operational metrics, not billing costs. Serverless infrastructure is outside this AWS account. S3 storage updates daily; standard-storage bytes are shown." } }],
    [for widget in [
      { type = "metric", properties = { title = "Databricks EC2 CPU (%)", metrics = [for id in sort(data.aws_instances.databricks.ids) : ["AWS/EC2", "CPUUtilization", "InstanceId", id]], stat = "Average", period = 300, region = var.aws_region } },
      { type = "metric", properties = { title = "Databricks EC2 network bytes", metrics = concat([], [for id in sort(data.aws_instances.databricks.ids) : [["AWS/EC2", "NetworkIn", "InstanceId", id], ["AWS/EC2", "NetworkOut", "InstanceId", id]]]...), stat = "Sum", period = 300, region = var.aws_region } },
      { type = "metric", properties = { title = "Databricks EC2 status check failures", metrics = [for id in sort(data.aws_instances.databricks.ids) : ["AWS/EC2", "StatusCheckFailed", "InstanceId", id]], stat = "Maximum", period = 300, region = var.aws_region } }
    ] : widget if length(data.aws_instances.databricks.ids) > 0],
    [for key, id in var.nat_gateway_ids : { type = "metric", properties = { title = "NAT ${key}: traffic bytes", metrics = [["AWS/NATGateway", "BytesInFromSource", "NatGatewayId", id], ["AWS/NATGateway", "BytesOutToSource", "NatGatewayId", id]], stat = "Sum", period = 300, region = var.aws_region } }],
    [for key, id in var.nat_gateway_ids : { type = "metric", properties = { title = "NAT ${key}: errors and packet drops", metrics = [["AWS/NATGateway", "ErrorPortAllocation", "NatGatewayId", id], ["AWS/NATGateway", "PacketsDropCount", "NatGatewayId", id]], stat = "Sum", period = 300, region = var.aws_region } }],
    [for key, bucket in var.bucket_names : { type = "metric", properties = { title = "S3 ${key}: standard storage bytes", metrics = [["AWS/S3", "BucketSizeBytes", "BucketName", bucket, "StorageType", "StandardStorage"]], stat = "Average", period = 86400, region = var.aws_region } }],
    [for key, bucket in var.bucket_names : { type = "metric", properties = { title = "S3 ${key}: object count", metrics = [["AWS/S3", "NumberOfObjects", "BucketName", bucket, "StorageType", "AllStorageTypes"]], stat = "Average", period = 86400, region = var.aws_region } }],
    [for key, id in var.ebs_volume_ids : { type = "metric", properties = { title = "EBS ${key}: read/write bytes", metrics = [["AWS/EBS", "VolumeReadBytes", "VolumeId", id], ["AWS/EBS", "VolumeWriteBytes", "VolumeId", id]], stat = "Sum", period = 300, region = var.aws_region } }],
    var.enable_s3_request_metrics ? [for key, bucket in var.bucket_names : { type = "metric", properties = { title = "S3 ${key}: requests and errors", metrics = [["AWS/S3", "AllRequests", "BucketName", bucket, "FilterId", "DatabricksObservability"], ["AWS/S3", "4xxErrors", "BucketName", bucket, "FilterId", "DatabricksObservability"], ["AWS/S3", "5xxErrors", "BucketName", bucket, "FilterId", "DatabricksObservability"]], stat = "Sum", period = 300, region = var.aws_region } }] : [],
    var.enable_s3_request_metrics ? [for key, bucket in var.bucket_names : { type = "metric", properties = { title = "S3 ${key}: transfer bytes", metrics = [["AWS/S3", "BytesDownloaded", "BucketName", bucket, "FilterId", "DatabricksObservability"], ["AWS/S3", "BytesUploaded", "BucketName", bucket, "FilterId", "DatabricksObservability"]], stat = "Sum", period = 300, region = var.aws_region } }] : []
  )
  nat_alarm_definitions = merge({}, [for key, id in var.nat_gateway_ids : {
    "${key}-port-allocation" = { gateway_id = id, metric = "ErrorPortAllocation" }
    "${key}-packet-drops"    = { gateway_id = id, metric = "PacketsDropCount" }
  }]...)
}

resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({ widgets = [for index, widget in local.widget_definitions : merge(widget, { x = (index % 2) * 12, y = floor(index / 2) * 6, width = 12, height = 6 })] })
}

resource "aws_cloudwatch_metric_alarm" "nat" {
  for_each            = local.nat_alarm_definitions
  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = "Databricks NAT gateway ${each.value.metric} detected."
  namespace           = "AWS/NATGateway"
  metric_name         = each.value.metric
  dimensions          = { NatGatewayId = each.value.gateway_id }
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_action_arns
  ok_actions          = var.alarm_action_arns
  tags                = var.tags
}
