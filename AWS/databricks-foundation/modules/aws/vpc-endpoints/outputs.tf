output "s3_gateway_endpoint_id" {
  description = "S3 gateway VPC endpoint ID."
  value       = aws_vpc_endpoint.s3.id
}

output "sts_interface_endpoint_id" {
  description = "STS interface VPC endpoint ID."
  value       = aws_vpc_endpoint.sts.id
}

output "kinesis_interface_endpoint_id" {
  description = "Kinesis Streams interface VPC endpoint ID."
  value       = aws_vpc_endpoint.kinesis.id
}

output "endpoint_security_group_id" {
  description = "Security group attached to the STS and Kinesis interface endpoint network interfaces."
  value       = aws_security_group.endpoint.id
}

output "endpoint_subnet_ids" {
  description = "Dedicated interface endpoint subnet IDs keyed by logical name."
  value       = { for name, subnet in aws_subnet.endpoint : name => subnet.id }
}
