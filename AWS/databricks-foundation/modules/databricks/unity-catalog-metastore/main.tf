resource "terraform_data" "validation" {
  input = {
    storage_root               = var.storage_root
    storage_root_credential_id = var.storage_root_credential_id
  }

  lifecycle {
    precondition {
      condition     = (var.storage_root == null) == (var.storage_root_credential_id == null)
      error_message = "storage_root and storage_root_credential_id must either both be set or both be null."
    }
  }
}

resource "databricks_metastore" "this" {
  provider = databricks.accounts

  name                       = var.metastore_name
  region                     = var.aws_region
  owner                      = var.owner
  storage_root               = var.storage_root
  storage_root_credential_id = var.storage_root_credential_id

  provider_config {
    workspace_id = var.workspace_id
  }

  depends_on = [terraform_data.validation]
}

resource "databricks_metastore_assignment" "workspace" {
  provider = databricks.accounts

  metastore_id = databricks_metastore.this.id
  workspace_id = var.workspace_id
}
