terraform {
  required_version = ">= 1.7.0, < 2.0.0"
  required_providers {
    databricks = {
      source                = "databricks/databricks"
      version               = ">= 1.100.0, < 2.0.0"
      configuration_aliases = [databricks.workspace]
    }
  }
}
