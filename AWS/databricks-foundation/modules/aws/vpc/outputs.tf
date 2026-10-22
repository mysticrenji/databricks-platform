output "vpc_id" {
  description = "VPC ID for subnet, routing, security group, and Databricks network components."
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "VPC ARN for IAM policies and integrations."
  value       = aws_vpc.this.arn
}

output "cidr_block" {
  description = "Primary IPv4 CIDR for subnet allocation and network rules."
  value       = aws_vpc.this.cidr_block
}
