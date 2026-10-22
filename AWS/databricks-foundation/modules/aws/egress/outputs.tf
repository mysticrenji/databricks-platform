output "internet_gateway_id" {
  description = "Internet gateway ID attached to the VPC."
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "NAT gateway IDs keyed by the corresponding nat_subnets key."
  value       = { for key, gateway in aws_nat_gateway.this : key => gateway.id }
}

output "nat_gateway_public_ips" {
  description = "Public Elastic IP addresses used for NAT egress, keyed by nat_subnets key."
  value       = { for key, elastic_ip in aws_eip.nat : key => elastic_ip.public_ip }
}

output "nat_subnet_ids" {
  description = "NAT subnet IDs keyed by nat_subnets key."
  value       = { for key, subnet in aws_subnet.nat : key => subnet.id }
}

output "workspace_route_table_ids" {
  description = "Private workspace route table IDs keyed by nat_subnets key."
  value       = { for key, route_table in aws_route_table.workspace : key => route_table.id }
}
