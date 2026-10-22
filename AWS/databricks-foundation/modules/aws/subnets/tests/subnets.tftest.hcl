mock_provider "aws" {}

variables {
  name   = "databricks-dev-workspace"
  vpc_id = "vpc-0123456789abcdef0"
  workspace_subnets = {
    az1 = {
      availability_zone = "eu-central-1a"
      cidr_block        = "10.20.0.0/20"
    }
    az2 = {
      availability_zone = "eu-central-1b"
      cidr_block        = "10.20.16.0/20"
    }
  }
}

run "creates_private_subnets_in_distinct_azs" {
  command = plan

  assert {
    condition     = !aws_subnet.workspace["az1"].map_public_ip_on_launch && !aws_subnet.workspace["az2"].map_public_ip_on_launch
    error_message = "Workspace subnets must not assign public IP addresses."
  }

  assert {
    condition     = output.availability_zones["az1"] != output.availability_zones["az2"]
    error_message = "Workspace subnets must be in distinct availability zones."
  }
}

run "rejects_single_subnet" {
  command = plan
  variables {
    workspace_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.0.0/20"
      }
    }
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_duplicate_availability_zone" {
  command = plan
  variables {
    workspace_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.0.0/20"
      }
      az2 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.16.0/20"
      }
    }
  }
  expect_failures = [terraform_data.validation]
}

run "rejects_invalid_subnet_mask" {
  command = plan
  variables {
    workspace_subnets = {
      az1 = {
        availability_zone = "eu-central-1a"
        cidr_block        = "10.20.0.0/16"
      }
      az2 = {
        availability_zone = "eu-central-1b"
        cidr_block        = "10.21.0.0/20"
      }
    }
  }
  expect_failures = [var.workspace_subnets]
}
