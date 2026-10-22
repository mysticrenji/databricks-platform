output "names" {
  description = "Storage credential names by purpose."
  value       = { for key, credential in databricks_storage_credential.this : key => credential.name }
}

output "trust" {
  description = "Credential-generated trust details consumed directly by the IAM role module in the same state."
  value = { for key, credential in databricks_storage_credential.this : key => {
    external_id           = credential.aws_iam_role[0].external_id
    unity_catalog_iam_arn = credential.aws_iam_role[0].unity_catalog_iam_arn
  } }
}
