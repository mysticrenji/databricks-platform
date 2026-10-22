mock_provider "aws" {}

variables {
  name   = "databricks-dev"
  vpc_id = "vpc-0123456789abcdef0"
  nat_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.240.0/24"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.241.0/24"
    }
  }
  workspace_subnet_ids = {
    az1 = "subnet-0123456789abcdef0"
    az2 = "subnet-0123456789abcdef1"
  }
  workspace_subnet_nat_gateway_keys = {
    az1 = "az1"
    az2 = "az2"
  }
}

run "creates_zonal_nat_egress_and_private_workspace_routes" {
  command = plan

  assert {
    condition     = aws_route.public_internet["az1"].destination_cidr_block == "0.0.0.0/0"
    error_message = "NAT subnet route tables must have a default route."
  }

  assert {
    condition     = aws_route.workspace_egress["az2"].destination_cidr_block == "0.0.0.0/0"
    error_message = "Workspace route tables must have a default egress route."
  }

  assert {
    condition     = aws_route_table_association.workspace["az1"].subnet_id == "subnet-0123456789abcdef0"
    error_message = "Each workspace subnet must have a private route table association."
  }
}

run "supports_single_nat_subnet" {
  command = plan
  variables {
    nat_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.240.0/24"
      }
    }
    workspace_subnet_nat_gateway_keys = {
      az1 = "az1"
      az2 = "az1"
    }
  }

  assert {
    condition     = aws_route_table_association.workspace["az2"].route_table_id == aws_route_table.workspace["az1"].id
    error_message = "A single NAT gateway must serve both workspace subnets through its private route table."
  }
}

run "rejects_unknown_nat_mapping" {
  command = plan
  variables {
    workspace_subnet_nat_gateway_keys = {
      az1 = "az1"
      az2 = "missing"
    }
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_noncanonical_nat_cidr" {
  command = plan
  variables {
    nat_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.240.1/24"
      }
      az2 = {
        availability_zone = "eu-central-1b"
        cidr_block        = "10.20.241.0/24"
      }
    }
  }
  expect_failures = [var.nat_subnets]
}
