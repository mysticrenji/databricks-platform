resource "terraform_data" "validation" {
  input = var.workspace_subnets

  lifecycle {
    precondition {
      condition     = length(var.workspace_subnets) >= 2
      error_message = "Databricks requires at least two workspace subnets."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.workspace_subnets) : subnet.availability_zone])) == length(var.workspace_subnets)
      error_message = "Each Databricks workspace subnet must be in a distinct availability zone."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.workspace_subnets) : subnet.cidr_block])) == length(var.workspace_subnets)
      error_message = "Each workspace subnet must have a distinct CIDR block."
    }
  }
}

resource "aws_subnet" "workspace" {
  for_each = var.workspace_subnets

  vpc_id                          = var.vpc_id
  availability_zone               = each.value.availability_zone
  cidr_block                      = each.value.cidr_block
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })

  depends_on = [terraform_data.validation]
}
