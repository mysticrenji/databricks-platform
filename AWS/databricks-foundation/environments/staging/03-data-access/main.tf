terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
}
# Scaffold only: metastore assignment, UC storage access, catalogs, and volumes.
