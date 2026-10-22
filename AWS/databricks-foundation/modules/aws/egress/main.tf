resource "terraform_data" "validation" {
  input = {
    nat_subnets                       = var.nat_subnets
    workspace_subnet_ids              = var.workspace_subnet_ids
    workspace_subnet_nat_gateway_keys = var.workspace_subnet_nat_gateway_keys
  }

  lifecycle {
    precondition {
      condition     = length(var.nat_subnets) >= 1
      error_message = "Provide at least one NAT subnet for Databricks egress."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.nat_subnets) : subnet.availability_zone])) == length(var.nat_subnets)
      error_message = "Each NAT subnet must be in a distinct availability zone."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.nat_subnets) : subnet.cidr_block])) == length(var.nat_subnets)
      error_message = "Each NAT subnet must have a distinct CIDR block."
    }

    precondition {
      condition     = length(var.workspace_subnet_ids) >= 2
      error_message = "Provide at least two Databricks workspace subnet IDs."
    }

    precondition {
      condition = length(var.workspace_subnet_ids) == length(var.workspace_subnet_nat_gateway_keys) && alltrue([
        for key in keys(var.workspace_subnet_ids) : contains(keys(var.workspace_subnet_nat_gateway_keys), key)
      ])
      error_message = "workspace_subnet_nat_gateway_keys must contain exactly one entry for every workspace_subnet_ids key."
    }

    precondition {
      condition     = alltrue([for key in values(var.workspace_subnet_nat_gateway_keys) : contains(keys(var.nat_subnets), key)])
      error_message = "Every workspace subnet must reference an existing nat_subnets key."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-igw"
  })
}

resource "aws_subnet" "nat" {
  for_each = var.nat_subnets

  vpc_id                          = var.vpc_id
  availability_zone               = each.value.availability_zone
  cidr_block                      = each.value.cidr_block
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.key}-nat"
  })

  depends_on = [terraform_data.validation]
}

resource "aws_eip" "nat" {
  for_each = var.nat_subnets

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}-nat-eip"
  })
}

resource "aws_nat_gateway" "this" {
  for_each = var.nat_subnets

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.nat[each.key].id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}-nat"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  for_each = var.nat_subnets

  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}-public"
  })
}

resource "aws_route" "public_internet" {
  for_each = var.nat_subnets

  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "nat" {
  for_each = var.nat_subnets

  subnet_id      = aws_subnet.nat[each.key].id
  route_table_id = aws_route_table.public[each.key].id
}

resource "aws_route_table" "workspace" {
  for_each = var.nat_subnets

  vpc_id = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}-workspace-private"
  })
}

resource "aws_route" "workspace_egress" {
  for_each = var.nat_subnets

  route_table_id         = aws_route_table.workspace[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "workspace" {
  for_each = var.workspace_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.workspace[var.workspace_subnet_nat_gateway_keys[each.key]].id

  depends_on = [terraform_data.validation]
}
