locals {
  group_role_assignments = merge({
    for assignment in flatten([
      for profile_key, profile in var.instance_profiles : [
        for group_id in profile.group_ids : {
          key         = "${profile_key}/${group_id}"
          profile_key = profile_key
          group_id    = group_id
        }
      ]
    ]) : assignment.key => assignment
    }, {
    for assignment in flatten([
      for profile_key, profile in var.instance_profiles : [
        for group_name, group_id in profile.group_ids_by_name : {
          key         = "${profile_key}/name/${group_name}"
          profile_key = profile_key
          group_id    = group_id
        }
      ]
    ]) : assignment.key => assignment
  })
}

resource "databricks_instance_profile" "this" {
  provider = databricks.workspace
  for_each = var.instance_profiles

  instance_profile_arn     = each.value.instance_profile_arn
  iam_role_arn             = each.value.iam_role_arn
  is_meta_instance_profile = each.value.is_meta_instance_profile
  skip_validation          = each.value.skip_validation
}

resource "databricks_group_role" "instance_profile" {
  provider = databricks.workspace
  for_each = local.group_role_assignments

  group_id = each.value.group_id
  role     = databricks_instance_profile.this[each.value.profile_key].id
}
