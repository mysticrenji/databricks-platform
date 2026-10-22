mock_provider "aws" {}

variables {
  name                        = "databricks-dev-eu-central-1"
  aws_region                  = "eu-central-1"
  vpc_id                      = "vpc-0123456789abcdef0"
  workspace_security_group_id = "sg-0123456789abcdef0"
  endpoint_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.242.0/24"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.243.0/24"
    }
  }
  workspace_route_table_ids = {
    az1 = "rtb-0123456789abcdef0"
    az2 = "rtb-0123456789abcdef1"
  }
}

run "creates_regional_private_endpoints" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway" && aws_vpc_endpoint.s3.service_name == "com.amazonaws.eu-central-1.s3"
    error_message = "S3 must use a regional gateway endpoint."
  }

  assert {
    condition     = aws_vpc_endpoint.sts.vpc_endpoint_type == "Interface" && aws_vpc_endpoint.sts.private_dns_enabled
    error_message = "STS must use an interface endpoint with private DNS enabled."
  }

  assert {
    condition     = aws_vpc_endpoint.kinesis.service_name == "com.amazonaws.eu-central-1.kinesis-streams"
    error_message = "Kinesis must use the regional Kinesis Streams endpoint."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.workspace_https.from_port == 443 && aws_vpc_security_group_ingress_rule.workspace_https.referenced_security_group_id == "sg-0123456789abcdef0"
    error_message = "Endpoint security group must permit HTTPS from the workspace security group."
  }
}

run "supports_shared_workspace_route_table" {
  command = plan
  variables {
    workspace_route_table_ids = {
      shared = "rtb-0123456789abcdef0"
    }
  }

  assert {
    condition     = toset(aws_vpc_endpoint.s3.route_table_ids) == toset(["rtb-0123456789abcdef0"])
    error_message = "The S3 gateway endpoint must attach to the shared workspace route table in single-NAT mode."
  }
}

run "rejects_empty_workspace_route_tables" {
  command = plan
  variables {
    workspace_route_table_ids = {}
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_single_endpoint_subnet" {
  command = plan
  variables {
    endpoint_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.242.0/24"
      }
    }
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_endpoint_subnet_smaller_than_recommended" {
  command = plan
  variables {
    endpoint_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.242.0/28"
      }
      az2 = {
        availability_zone = "eu-central-1b"
        cidr_block        = "10.20.243.0/24"
      }
    }
  }
  expect_failures = [var.endpoint_subnets]
}
