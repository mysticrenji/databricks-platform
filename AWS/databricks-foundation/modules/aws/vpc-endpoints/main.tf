resource "terraform_data" "validation" {
  input = {
    endpoint_subnets          = var.endpoint_subnets
    workspace_route_table_ids = var.workspace_route_table_ids
  }

  lifecycle {
    precondition {
      condition     = length(var.endpoint_subnets) >= 2
      error_message = "Provide at least two endpoint subnets for high availability."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.endpoint_subnets) : subnet.availability_zone])) == length(var.endpoint_subnets)
      error_message = "Each endpoint subnet must be in a distinct availability zone."
    }

    precondition {
      condition     = length(distinct([for subnet in values(var.endpoint_subnets) : subnet.cidr_block])) == length(var.endpoint_subnets)
      error_message = "Each endpoint subnet must have a distinct CIDR block."
    }

    precondition {
      condition     = length(var.workspace_route_table_ids) >= 1
      error_message = "Provide at least one private workspace route table for the S3 gateway endpoint."
    }
  }
}

resource "aws_subnet" "endpoint" {
  for_each = var.endpoint_subnets

  vpc_id                          = var.vpc_id
  availability_zone               = each.value.availability_zone
  cidr_block                      = each.value.cidr_block
  map_public_ip_on_launch         = false
  assign_ipv6_address_on_creation = false

  tags = merge(var.tags, each.value.tags, {
    Name = "${var.name}-${each.key}-endpoint"
  })

  depends_on = [terraform_data.validation]
}

resource "aws_security_group" "endpoint" {
  name        = "${var.name}-endpoints"
  description = "HTTPS ingress from Databricks workspace subnets to AWS interface VPC endpoints"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-endpoints"
  })
}

resource "aws_vpc_security_group_ingress_rule" "workspace_https" {
  security_group_id            = aws_security_group.endpoint.id
  referenced_security_group_id = var.workspace_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "HTTPS from Databricks workspace security group"
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values(var.workspace_route_table_ids)

  tags = merge(var.tags, {
    Name = "${var.name}-s3"
  })

  depends_on = [terraform_data.validation]
}

resource "aws_vpc_endpoint" "sts" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.sts"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = values(aws_subnet.endpoint)[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name}-sts"
  })
}

resource "aws_vpc_endpoint" "kinesis" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.kinesis-streams"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = values(aws_subnet.endpoint)[*].id
  security_group_ids  = [aws_security_group.endpoint.id]
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.name}-kinesis"
  })
}
