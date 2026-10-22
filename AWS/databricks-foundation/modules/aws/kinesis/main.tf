locals {
  compute_consumer_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ConsumeConfiguredStream"
      Effect = "Allow"
      Action = [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListShards",
      ]
      Resource = aws_kinesis_stream.this.arn
    }]
  })
}

resource "aws_kinesis_stream" "this" {
  name             = var.name
  retention_period = var.retention_period_hours

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy" "compute_consumer" {
  name   = "${var.name}-consumer"
  role   = var.workspace_instance_profile_role_name
  policy = local.compute_consumer_policy
}
