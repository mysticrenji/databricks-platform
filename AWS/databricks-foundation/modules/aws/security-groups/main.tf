locals {
  databricks_egress_tcp_rules = merge(
    {
      https = {
        description = "Databricks infrastructure, cloud data sources, and library repositories"
        from_port   = 443
        to_port     = 443
      }
      legacy_hive_metastore = {
        description = "Legacy Hive metastore"
        from_port   = 3306
        to_port     = 3306
      }
      custom_dns = {
        description = "Custom DNS resolution"
        from_port   = 53
        to_port     = 53
      }
      lakebase = {
        description = "Lakebase"
        from_port   = 5432
        to_port     = 5432
      }
      control_plane_api = {
        description = "Databricks compute-plane control-plane API"
        from_port   = 8443
        to_port     = 8445
      }
      unity_catalog_lineage = {
        description = "Unity Catalog logging and lineage"
        from_port   = 8444
        to_port     = 8444
      }
      reserved_databricks = {
        description = "Reserved for future Databricks use"
        from_port   = 8446
        to_port     = 8451
      }
    },
    var.enable_privatelink ? {
      secure_cluster_connectivity = {
        description = "Secure cluster connectivity through PrivateLink"
        from_port   = 6666
        to_port     = 6666
      }
    } : {},
    var.enable_fips ? {
      fips = {
        description = "FIPS encryption"
        from_port   = 2443
        to_port     = 2443
      }
    } : {},
  )
}

resource "aws_security_group" "workspace" {
  name        = var.name
  description = "Databricks workspace security group"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_vpc_security_group_ingress_rule" "self_tcp" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Databricks internal TCP traffic"
}

resource "aws_vpc_security_group_ingress_rule" "self_udp" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "udp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Databricks internal UDP traffic"
}

resource "aws_vpc_security_group_egress_rule" "self_tcp" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "tcp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Databricks internal TCP traffic"
}

resource "aws_vpc_security_group_egress_rule" "self_udp" {
  security_group_id            = aws_security_group.workspace.id
  referenced_security_group_id = aws_security_group.workspace.id
  ip_protocol                  = "udp"
  from_port                    = 0
  to_port                      = 65535
  description                  = "Databricks internal UDP traffic"
}

resource "aws_vpc_security_group_egress_rule" "databricks_tcp" {
  for_each = local.databricks_egress_tcp_rules

  security_group_id = aws_security_group.workspace.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  description       = each.value.description
}
