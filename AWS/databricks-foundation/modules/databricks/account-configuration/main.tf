resource "terraform_data" "validation" {
  input = {
    subnet_ids = var.workspace_subnet_ids
  }

  lifecycle {
    precondition {
      condition     = length(var.workspace_subnet_ids) >= 2
      error_message = "Databricks network configurations require at least two workspace subnet IDs."
    }

    precondition {
      condition     = length(distinct(var.workspace_subnet_ids)) == length(var.workspace_subnet_ids)
      error_message = "workspace_subnet_ids must not contain duplicates."
    }
  }
}

resource "databricks_mws_credentials" "this" {
  provider = databricks.accounts

  credentials_name = "${var.name}-credentials"
  role_arn         = var.cross_account_role_arn
}

resource "databricks_mws_storage_configurations" "this" {
  provider = databricks.accounts

  account_id                 = var.databricks_account_id
  storage_configuration_name = "${var.name}-storage"
  bucket_name                = var.root_storage_bucket_name
}

resource "databricks_mws_networks" "this" {
  provider = databricks.accounts

  account_id         = var.databricks_account_id
  network_name       = "${var.name}-network"
  vpc_id             = var.vpc_id
  subnet_ids         = sort(var.workspace_subnet_ids)
  security_group_ids = [var.workspace_security_group_id]

  depends_on = [terraform_data.validation]
}
