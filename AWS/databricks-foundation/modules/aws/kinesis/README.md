# Kinesis stream

Creates one Amazon Kinesis Data Stream in on-demand mode and gives the existing
Databricks compute instance-profile role least-privilege **consumer** access to
that stream.

The policy permits `DescribeStream`, `DescribeStreamSummary`, `ListShards`,
`GetShardIterator`, and `GetRecords` for only the stream created by this module.
It deliberately does not allow publishing records, creating streams, or access
to other streams. The development VPC already creates a Kinesis interface
endpoint, so classic compute can use the private AWS service endpoint.

## Inputs

| Name | Required | Default | Description |
| --- | --- | --- | --- |
| `name` | yes | — | Kinesis Data Stream name. |
| `workspace_instance_profile_role_name` | yes | — | Existing Databricks compute role name. |
| `retention_period_hours` | no | `24` | Record retention, from 24 through 8760 hours. |
| `tags` | no | `{}` | Additional stream tags. |

## Outputs

| Name | Description |
| --- | --- |
| `stream_arn` | ARN to use from a Databricks job or notebook. |
| `stream_name` | Created stream name. |

Use the module from `01-infra` by configuring `kinesis_stream` in that root's
tfvars. Apply `01-infra`, then register and allow the instance profile in
`04-workspace` before users create compute that consumes the stream.
