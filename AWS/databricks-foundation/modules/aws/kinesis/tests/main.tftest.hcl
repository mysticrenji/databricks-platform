mock_provider "aws" {}

run "creates_an_on_demand_stream_and_consumer_policy" {
  command = plan

  variables {
    name                                 = "databricks-dev-events"
    workspace_instance_profile_role_name = "databricks-dev-compute"
  }

  assert {
    condition     = aws_kinesis_stream.this.name == "databricks-dev-events"
    error_message = "The configured stream name must be used."
  }

  assert {
    condition     = aws_kinesis_stream.this.stream_mode_details[0].stream_mode == "ON_DEMAND"
    error_message = "The stream must use on-demand capacity."
  }

  assert {
    condition     = aws_iam_role_policy.compute_consumer.role == "databricks-dev-compute"
    error_message = "The consumer policy must be attached to the compute instance-profile role."
  }
}
