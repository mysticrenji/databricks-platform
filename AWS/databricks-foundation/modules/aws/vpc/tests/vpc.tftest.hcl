mock_provider "aws" {}

variables {
  name       = "databricks-test-vpc"
  cidr_block = "10.20.0.0/16"
}

run "valid_private_ranges" {
  command = plan

  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "Databricks requires both VPC DNS settings."
  }
}

run "accept_172_private_range" {
  command = plan
  variables {
    cidr_block = "172.31.0.0/16"
  }
}

run "accept_smallest_databricks_vpc" {
  command = plan
  variables {
    cidr_block = "192.168.0.0/25"
  }
}

run "reject_public_range" {
  command = plan
  variables {
    cidr_block = "172.32.0.0/16"
  }
  expect_failures = [var.cidr_block]
}

run "reject_too_small" {
  command = plan
  variables {
    cidr_block = "10.20.0.0/26"
  }
  expect_failures = [var.cidr_block]
}

run "reject_host_bits" {
  command = plan
  variables {
    cidr_block = "10.20.0.1/16"
  }
  expect_failures = [var.cidr_block]
}

run "reject_ipv6" {
  command = plan
  variables {
    cidr_block = "fd00::/16"
  }
  expect_failures = [var.cidr_block]
}

run "reject_malformed_cidr" {
  command = plan
  variables {
    cidr_block = "invalid"
  }
  expect_failures = [var.cidr_block]
}
