terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
  required_providers {
    databricks = { source = "databricks/databricks", version = ">= 1.100.0, < 2.0.0" }
  }
}

provider "databricks" {
  alias = "workspace"
  host  = data.terraform_remote_state.account.outputs.workspace_url
}
