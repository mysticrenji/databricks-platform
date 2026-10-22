output "dashboard_name" {
  description = "CloudWatch dashboard name."
  value       = aws_cloudwatch_dashboard.this.dashboard_name
}
output "dashboard_arn" {
  description = "CloudWatch dashboard ARN."
  value       = aws_cloudwatch_dashboard.this.dashboard_arn
}
output "alarm_arns" {
  description = "NAT alarm ARNs keyed by gateway logical name and failure type."
  value       = { for key, alarm in aws_cloudwatch_metric_alarm.nat : key => alarm.arn }
}
output "discovered_instance_ids" {
  description = "Running Databricks-tagged EC2 instances discovered during the latest Terraform refresh."
  value       = data.aws_instances.databricks.ids
}
