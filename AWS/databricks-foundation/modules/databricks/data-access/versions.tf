terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
    databricks = {
      source                = "databricks/databricks"
      version               = ">= 1.100.0, < 2.0.0"
      configuration_aliases = [databricks.workspace]
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.13.0, < 1.0.0"
    }
  }
}
