variable "credentials" {
  description = "Credentials keyed by storage purpose, referencing deterministic planned IAM role ARNs."
  type = map(object({
    name     = string
    role_arn = string
  }))
  nullable = false
  default  = {}
  validation {
    condition     = alltrue([for credential in values(var.credentials) : length(trimspace(credential.name)) > 0 && can(regex("^arn:aws(-us-gov)?:iam::[0-9]{12}:role/.+$", credential.role_arn))])
    error_message = "Each credential requires a nonempty name and AWS IAM role ARN."
  }
}
