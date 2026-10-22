resource "databricks_storage_credential" "this" {
  provider        = databricks.workspace
  for_each        = var.credentials
  name            = each.value.name
  isolation_mode  = "ISOLATION_MODE_ISOLATED"
  skip_validation = false
  force_destroy   = false
  comment         = "Dedicated Unity Catalog S3 access; managed by Terraform."
  aws_iam_role {
    role_arn = each.value.role_arn
  }
}
