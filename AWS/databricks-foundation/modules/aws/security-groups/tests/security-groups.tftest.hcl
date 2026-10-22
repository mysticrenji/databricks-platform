mock_provider "aws" {}

variables {
  name   = "databricks-dev-workspace"
  vpc_id = "vpc-0123456789abcdef0"
}

run "creates_required_workspace_rules" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.self_tcp.from_port == 0 && aws_vpc_security_group_ingress_rule.self_tcp.to_port == 65535
    error_message = "Databricks requires unrestricted internal TCP traffic within its security group."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.self_udp.ip_protocol == "udp"
    error_message = "Databricks requires unrestricted internal UDP traffic within its security group."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.databricks_tcp["https"].from_port == 443
    error_message = "Databricks requires HTTPS egress."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.databricks_tcp["reserved_databricks"].to_port == 8451
    error_message = "Databricks reserved outbound ports must be present."
  }
}

run "adds_privatelink_port_only_when_enabled" {
  command = plan
  variables {
    enable_privatelink = true
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.databricks_tcp["secure_cluster_connectivity"].from_port == 6666
    error_message = "PrivateLink requires TCP 6666."
  }
}

run "adds_fips_port_only_when_enabled" {
  command = plan
  variables {
    enable_fips = true
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.databricks_tcp["fips"].from_port == 2443
    error_message = "FIPS requires TCP 2443."
  }
}
