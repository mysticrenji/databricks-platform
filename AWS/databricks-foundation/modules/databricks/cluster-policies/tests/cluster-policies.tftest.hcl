mock_provider "databricks" {
  alias = "workspace"
}

variables {
  cluster_policies = {
    "shared-engineering" = {
      definition = {
        "spark_version" = {
          type  = "fixed"
          value = "auto:latest-lts"
        }
        "num_workers" = {
          type         = "range"
          minValue     = 1
          maxValue     = 8
          defaultValue = 2
        }
      }
      max_clusters_per_user = 2
      permissions = {
        groups = {
          "data-engineers" = "CAN_USE"
        }
      }
    }
  }
}

run "creates_policy_with_explicit_access" {
  command = plan

  assert {
    condition     = jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["num_workers"].maxValue == 8
    error_message = "The HCL policy definition must be serialized as cluster-policy JSON."
  }

  assert {
    condition     = databricks_cluster_policy.this["shared-engineering"].max_clusters_per_user == 2
    error_message = "The user cluster limit must be applied."
  }

  assert {
    condition     = length(databricks_permissions.cluster_policy["shared-engineering"].access_control) == 1
    error_message = "The configured group permission must be managed."
  }
}

run "allows_policy_without_cluster_limit" {
  command = plan

  variables {
    cluster_policies = {
      unlimited = { definition = { "num_workers" = { type = "fixed", value = 0 } } }
    }
  }

  assert {
    condition     = var.cluster_policies["unlimited"].max_clusters_per_user == null && contains(keys(output.cluster_policy_ids), "unlimited")
    error_message = "An omitted optional cluster limit must validate and allow policy creation."
  }
}

run "rejects_fractional_cluster_limit" {
  command = plan

  variables {
    cluster_policies = {
      invalid = {
        definition            = {}
        max_clusters_per_user = 1.5
      }
    }
  }

  expect_failures = [var.cluster_policies]
}

run "allows_mixed_type_policy_rules" {
  command = plan

  variables {
    cluster_policies = {
      direct = {
        definition = {
          "num_workers"    = { type = "fixed", value = 0 }
          "spark_version"  = { type = "allowlist", values = ["auto:latest-lts"] }
          "is_single_node" = { type = "fixed", value = true }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(databricks_cluster_policy.this["direct"].definition)["num_workers"].value == 0
    error_message = "Direct policies must preserve mixed numeric, list, and boolean rules without map coercion."
  }
}

run "allows_mixed_type_family_rules" {
  command = plan

  variables {
    cluster_policies = {
      family = {
        policy_family_id = "personal-vm"
        policy_family_definition_overrides = {
          "num_workers"    = { type = "fixed", value = 0 }
          "spark_version"  = { type = "allowlist", values = ["auto:latest-lts"] }
          "is_single_node" = { type = "fixed", value = true }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(databricks_cluster_policy.this["family"].policy_family_definition_overrides)["is_single_node"].value == true
    error_message = "Family policies must preserve mixed numeric, list, and boolean rules without map coercion."
  }
}

run "allows_policy_family_with_overrides" {
  command = plan

  variables {
    cluster_policies = {
      "family-policy" = {
        policy_family_id = "personal-vm"
        policy_family_definition_overrides = {
          "autotermination_minutes" = {
            type  = "fixed"
            value = 60
          }
        }
      }
    }
  }

  assert {
    condition     = databricks_cluster_policy.this["family-policy"].policy_family_id == "personal-vm"
    error_message = "Policy-family policies must retain the selected family."
  }
}

run "rejects_definition_and_policy_family_together" {
  command = plan

  variables {
    cluster_policies = {
      invalid = {
        definition       = {}
        policy_family_id = "personal-vm"
      }
    }
  }

  expect_failures = [terraform_data.validation]
}
run "enforces_volume_logging" {
  command = plan
  variables {
    cluster_log_volume_path = "/Volumes/dev_operations/observability/cluster_logs"
  }
  assert {
    condition     = jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["cluster_log_conf.type"].value == "VOLUMES" && jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["cluster_log_conf.path"].value == var.cluster_log_volume_path && jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["num_workers"].maxValue == 8
    error_message = "Policy must enforce the UC log path and retain existing compute restrictions."
  }
}

run "enforces_volume_logging_for_family_without_overrides" {
  command = plan
  variables {
    cluster_log_volume_path = "/Volumes/dev_operations/observability/cluster_logs"
    cluster_policies        = { family = { policy_family_id = "personal-vm" } }
  }
  assert {
    condition     = jsondecode(databricks_cluster_policy.this["family"].policy_family_definition_overrides)["cluster_log_conf.path"].value == var.cluster_log_volume_path
    error_message = "Logging enforcement must also apply to policy-family configurations."
  }
}

run "rejects_invalid_log_path" {
  command = plan
  variables { cluster_log_volume_path = "s3://logs" }
  expect_failures = [var.cluster_log_volume_path]
}
run "enforces_volume_init_script" {
  command = plan
  variables {
    init_script_volume_path = "/Volumes/dev_operations/observability/init_scripts/hello-world.sh"
  }
  assert {
    condition     = jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["init_scripts.0.volumes.destination"].value == var.init_script_volume_path && jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["num_workers"].maxValue == 8
    error_message = "The script must be fixed at index zero without removing compute restrictions."
  }
}

run "enforces_family_init_script_without_logging" {
  command = plan
  variables {
    init_script_volume_path = "/Volumes/dev_operations/observability/init_scripts/hello-world.sh"
    cluster_policies        = { family = { policy_family_id = "personal-vm" } }
  }
  assert {
    condition     = jsondecode(databricks_cluster_policy.this["family"].policy_family_definition_overrides)["init_scripts.0.volumes.destination"].type == "fixed"
    error_message = "Policy-family configurations must enforce the init script even when logging is disabled."
  }
}

run "rejects_conflicting_index_zero_source" {
  command = plan
  variables {
    init_script_volume_path = "/Volumes/dev_operations/observability/init_scripts/hello-world.sh"
    cluster_policies = {
      conflicting = { definition = { "init_scripts.0.s3.destination" = { type = "fixed", value = "s3://old/script.sh" } } }
    }
  }
  expect_failures = [terraform_data.validation]
}
run "uploads_demo_before_policy_configuration" {
  command = apply
  variables {
    enable_hello_world_init_script = true
    init_script_volume_path        = "/Volumes/dev_operations/observability/init_scripts/hello-world.sh"
  }
  assert {
    condition     = output.hello_world_init_script_path == var.init_script_volume_path && strcontains(base64decode(databricks_file.hello_world_init_script["hello"].content_base64), "Hello world") && jsondecode(databricks_cluster_policy.this["shared-engineering"].definition)["init_scripts.0.volumes.destination"].value == output.hello_world_init_script_path
    error_message = "The compute-policy module must upload the bundled script and enforce the same path."
  }
}

run "rejects_upload_without_destination" {
  command = plan
  variables {
    enable_hello_world_init_script = true
    init_script_volume_path        = null
  }
  expect_failures = [terraform_data.validation]
}
