mock_provider "databricks" {
  alias = "workspace"
}

variables {
  instance_profiles = {
    data_access = {
      instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-data-access"
      iam_role_arn         = "arn:aws:iam::123456789012:role/databricks-data-access"
      group_ids            = ["group-id-data-engineers"]
    }
  }
}

run "registers_profile_and_grants_only_selected_groups" {
  command = plan

  assert {
    condition     = databricks_instance_profile.this["data_access"].instance_profile_arn == "arn:aws:iam::123456789012:instance-profile/databricks-data-access"
    error_message = "The AWS instance profile must be registered."
  }

  assert {
    condition     = !databricks_instance_profile.this["data_access"].skip_validation
    error_message = "Instance-profile validation must remain enabled by default."
  }

  assert {
    condition     = databricks_group_role.instance_profile["data_access/group-id-data-engineers"].group_id == "group-id-data-engineers"
    error_message = "Only explicitly selected groups may use the instance profile."
  }
}

run "registers_profile_without_delegating_usage" {
  command = plan

  variables {
    instance_profiles = {
      data_access = {
        instance_profile_arn = "arn:aws:iam::123456789012:instance-profile/databricks-data-access"
      }
    }
  }

  assert {
    condition     = length(databricks_group_role.instance_profile) == 0
    error_message = "No group access must be granted unless group_ids is configured."
  }
}

run "rejects_non_instance_profile_arn" {
  command = plan

  variables {
    instance_profiles = {
      invalid = {
        instance_profile_arn = "arn:aws:iam::123456789012:role/not-an-instance-profile"
      }
    }
  }

  expect_failures = [var.instance_profiles]
}
