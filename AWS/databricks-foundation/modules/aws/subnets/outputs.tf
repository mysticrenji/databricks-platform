output "subnet_ids" {
  description = "Workspace subnet IDs keyed by logical name."
  value       = { for name, subnet in aws_subnet.workspace : name => subnet.id }
}

output "subnet_ids_list" {
  description = "Workspace subnet IDs in stable logical-name order, for Databricks network registration."
  value       = [for name in sort(keys(aws_subnet.workspace)) : aws_subnet.workspace[name].id]
}

output "subnet_cidr_blocks" {
  description = "Workspace subnet IPv4 CIDRs keyed by logical name."
  value       = { for name, subnet in aws_subnet.workspace : name => subnet.cidr_block }
}

output "availability_zones" {
  description = "Availability Zone of each workspace subnet keyed by logical name."
  value       = { for name, subnet in aws_subnet.workspace : name => subnet.availability_zone }
}
