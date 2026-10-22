data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  # These ARNs deliberately do not reference the IAM role resources. Credentials
  # must be registered first so their external IDs can populate the role trust.
  role_arns = {
    for key, bucket in var.buckets : key =>
    "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.name}-uc-${key}"
  }
}

resource "terraform_data" "observability_validation" {
  lifecycle {
    precondition {
      condition     = !var.enable_init_scripts_volume || var.observability != null
      error_message = "The init-scripts volume requires the operations catalog (observability)."
    }
    precondition {
      condition     = !var.enable_init_scripts_volume || (var.observability == null ? true : var.observability.volume_name != "init_scripts")
      error_message = "The logs volume and init_scripts volume must have different names."
    }
    precondition {
      condition     = var.observability == null || contains(keys(var.buckets), "observability")
      error_message = "Apply 01-infra with enable_observability_bucket=true before enabling the operations catalog."
    }
    precondition {
      condition     = var.observability == null ? true : var.observability.catalog_name != var.catalog_name
      error_message = "Operations and analytics catalogs must have different names."
    }
  }
}

module "storage_credentials" {
  source    = "../storage-credentials"
  providers = { databricks.workspace = databricks.workspace }
  credentials = {
    for key, arn in local.role_arns : key => {
      name     = "${var.name}-${key}"
      role_arn = arn
    }
  }
}

module "uc_storage_roles" {
  source  = "../../../modules/aws/uc-storage-roles"
  name    = var.name
  buckets = var.buckets
  trust   = module.storage_credentials.trust
}

resource "time_sleep" "iam_propagation" {
  create_duration = "60s"
  triggers = {
    trust = sha256(jsonencode(module.storage_credentials.trust))
    roles = sha256(jsonencode(local.role_arns))
  }
  depends_on = [module.uc_storage_roles]
}

module "external_locations" {
  source    = "../external-locations"
  providers = { databricks.workspace = databricks.workspace }
  external_locations = {
    for key, name in module.storage_credentials.names : name => {
      url             = "${var.buckets[key].url}/${key == "landing" ? "landing" : "managed"}"
      credential_name = name
    }
  }
  depends_on = [time_sleep.iam_propagation]
}

module "catalogs" {
  source    = "../catalogs"
  providers = { databricks.workspace = databricks.workspace }
  catalogs = var.catalog_name == null ? {} : {
    (var.catalog_name) = {
      storage_root = "${var.buckets["uc_managed"].url}/managed/${var.catalog_name}"
      grants       = var.catalog_grants
      schemas = {
        bronze = { grants = lookup(var.schema_grants, "bronze", {}) }
        silver = { grants = lookup(var.schema_grants, "silver", {}) }
        gold   = { grants = lookup(var.schema_grants, "gold", {}) }
        ingestion = {
          grants = lookup(var.schema_grants, "ingestion", {})
          volumes = {
            incoming = {
              volume_type      = "EXTERNAL"
              grants           = var.incoming_volume_grants
              storage_location = "${var.buckets["landing"].url}/landing/incoming"
            }
          }
        }
      }
    }
  }
  depends_on = [module.external_locations]
}

module "observability_catalog" {
  source    = "../catalogs"
  providers = { databricks.workspace = databricks.workspace }
  catalogs = var.observability == null ? {} : {
    (var.observability.catalog_name) = {
      storage_root = "${try(var.buckets["observability"].url, "s3://missing-observability-bucket")}/managed/${var.observability.catalog_name}"
      grants       = var.observability.catalog_grants
      schemas = {
        (var.observability.schema_name) = {
          grants = var.observability.schema_grants
          volumes = merge({
            (var.observability.volume_name) = {
              volume_type = "MANAGED"
              grants      = var.observability.volume_grants
            }
            }, var.enable_init_scripts_volume ? {
            init_scripts = {
              volume_type = "MANAGED"
              grants      = { for principal in var.init_script_readers : principal => toset(["READ_VOLUME"]) }
            }
          } : {})
        }
      }
    }
  }
  depends_on = [terraform_data.observability_validation, module.external_locations]
}

removed {
  from = databricks_file.hello_world_init_script
  lifecycle {
    destroy = false
  }
}
