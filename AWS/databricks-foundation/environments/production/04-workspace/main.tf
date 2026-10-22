terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  backend "s3" {}
}
# Scaffold only: workspace identities, profiles, policies, warehouses, and jobs.
