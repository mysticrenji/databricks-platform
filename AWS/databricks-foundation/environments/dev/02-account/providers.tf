terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
  required_providers {
    databricks = { source = "databricks/databricks", version = ">= 1.100.0, < 2.0.0" }
  }
}

provider "databricks" {
  alias      = "accounts"
  host       = "https://accounts.cloud.databricks.com"
  account_id = var.databricks_account_id
}
