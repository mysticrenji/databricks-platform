terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.100.0, < 2.0.0"
    }
  }
}

provider "aws" {
  region = data.terraform_remote_state.infra.outputs.aws_region
  default_tags {
    tags = { Project = "databricks", Environment = "dev", ManagedBy = "Terraform" }
  }
}

provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.account.outputs.workspace_url
}

provider "databricks" {
  alias      = "accounts"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}
