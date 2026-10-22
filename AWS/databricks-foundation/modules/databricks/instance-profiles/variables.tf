variable "instance_profiles" {
  description = "AWS instance profiles to register, keyed by a stable Terraform identifier. group_ids grants selected workspace groups permission to use a profile."
  type = map(object({
    instance_profile_arn     = string
    iam_role_arn             = optional(string)
    is_meta_instance_profile = optional(bool, false)
    skip_validation          = optional(bool, false)
    group_ids                = optional(set(string), [])
    group_ids_by_name        = optional(map(string), {})
  }))
  nullable = false

  validation {
    condition = alltrue([
      for profile in values(var.instance_profiles) : can(regex("^arn:(aws|aws-us-gov):iam::[0-9]{12}:instance-profile/.+$", profile.instance_profile_arn))
    ])
    error_message = "Each instance_profile_arn must be an AWS IAM instance-profile ARN."
  }

  validation {
    condition = alltrue([
      for profile in values(var.instance_profiles) : profile.iam_role_arn == null || can(regex("^arn:(aws|aws-us-gov):iam::[0-9]{12}:role/.+$", profile.iam_role_arn))
    ])
    error_message = "Each iam_role_arn must be null or an AWS IAM role ARN."
  }

  validation {
    condition = alltrue(flatten([
      for profile in values(var.instance_profiles) : [
        for group_id in profile.group_ids : length(trimspace(group_id)) > 0 && group_id == trimspace(group_id)
      ]
    ]))
    error_message = "Each group_ids value must be non-empty with no leading or trailing whitespace."
  }
}
