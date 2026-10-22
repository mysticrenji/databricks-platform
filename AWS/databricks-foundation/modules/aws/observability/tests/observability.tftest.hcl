mock_provider "aws" {
  mock_data "aws_instances" {
    defaults = { ids = ["i-0123456789abcdef0"] }
  }
}
variables {
  name            = "databricks-dev-infra"
  aws_region      = "eu-central-1"
  vpc_id          = "vpc-0123456789abcdef0"
  nat_gateway_ids = { az1 = "nat-0123456789abcdef0" }
  bucket_names    = { root = "databricks-test-root" }
}
run "scoped_dashboard_and_safe_defaults" {
  command = plan
  assert {
    condition     = data.aws_instances.databricks.instance_tags["Vendor"] == "Databricks" && one(data.aws_instances.databricks.filter).name == "vpc-id" && one(one(data.aws_instances.databricks.filter).values) == var.vpc_id
    error_message = "Instance discovery must be scoped to Databricks in the selected VPC."
  }
  assert {
    condition     = length(aws_s3_bucket_metric.requests) == 0 && length(aws_cloudwatch_metric_alarm.nat) == 2
    error_message = "S3 request metrics must default off and each NAT must get two alarms."
  }
  assert {
    condition     = alltrue([for alarm in aws_cloudwatch_metric_alarm.nat : alarm.threshold == 0 && alarm.evaluation_periods == 2 && alarm.treat_missing_data == "notBreaching" && alarm.dimensions.NatGatewayId == var.nat_gateway_ids.az1 && length(alarm.alarm_actions) == 0])
    error_message = "NAT alarms must monitor the intended gateway without invented recipients."
  }
  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets) == 8 && alltrue([for widget in jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets : try(widget.properties.region == var.aws_region, widget.type == "text")])
    error_message = "Dashboard must contain scoped EC2, NAT, and S3 widgets in the selected region."
  }
}
run "ec2_network_metric_arrays" {
  command = plan
  assert {
    condition     = jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets[2].properties.metrics == [["AWS/EC2", "NetworkIn", "InstanceId", "i-0123456789abcdef0"], ["AWS/EC2", "NetworkOut", "InstanceId", "i-0123456789abcdef0"]]
    error_message = "EC2 network metrics must retain separate valid CloudWatch metric arrays."
  }
}
run "optional_requests_and_notifications" {
  command = plan
  variables {
    enable_s3_request_metrics = true
    alarm_action_arns         = ["arn:aws:sns:eu-central-1:123456789012:infra-alerts"]
    ebs_volume_ids            = { driver = "vol-0123456789abcdef0" }
  }
  assert {
    condition     = aws_s3_bucket_metric.requests["root"].bucket == var.bucket_names.root && aws_s3_bucket_metric.requests["root"].name == "DatabricksObservability" && length(jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets) == 11
    error_message = "Opt-in request metrics and EBS widgets must be added for configured resources."
  }
  assert {
    condition     = alltrue([for alarm in aws_cloudwatch_metric_alarm.nat : toset(alarm.alarm_actions) == var.alarm_action_arns && toset(alarm.ok_actions) == var.alarm_action_arns])
    error_message = "Alarm and recovery notifications must target only configured topics."
  }
}
run "no_running_compute" {
  command = plan
  override_data {
    target = data.aws_instances.databricks
    values = { ids = [] }
  }
  assert {
    condition     = length(jsondecode(aws_cloudwatch_dashboard.this.dashboard_body).widgets) == 5
    error_message = "An empty instance discovery must omit EC2 widgets while retaining infra metrics."
  }
}
run "rejects_invalid_topic" {
  command = plan
  variables { alarm_action_arns = ["invalid"] }
  expect_failures = [var.alarm_action_arns]
}
run "rejects_invalid_name" {
  command = plan
  variables { name = "invalid dashboard name" }
  expect_failures = [var.name]
}
