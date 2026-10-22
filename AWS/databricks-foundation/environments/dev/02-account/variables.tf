variable "environment_name" {
  description = "Expected environment identity from the infrastructure state."
  type        = string
  default     = "dev"
}

variable "workspace_key" {
  description = "Expected workspace identity from the infrastructure state."
  type        = string
  default     = "shared"
}

variable "state_bucket" {
  description = "Existing S3 bucket containing the development phase states."
  type        = string
  nullable    = false
}

variable "state_region" {
  description = "AWS Region of the S3 state bucket."
  type        = string
  nullable    = false
}

variable "infra_state_key" {
  description = "S3 key written by 01-infra."
  type        = string
  nullable    = false
  default     = "databricks/dev/shared/01-infra.tfstate"
}

variable "databricks_account_id" {
  description = "Databricks account ID used by the account provider."
  type        = string
  nullable    = false
}

variable "workspace_name" {
  description = "Databricks workspace name."
  type        = string
  nullable    = false
}

variable "pricing_tier" {
  description = "Databricks workspace pricing tier."
  type        = string
  nullable    = false
  default     = "PREMIUM"
}

variable "account_groups" {
  description = "Account groups, existing member SCIM IDs, and USER or ADMIN access to this workspace."
  type = map(object({
    member_ids           = optional(map(string), {})
    workspace_permission = optional(string, "USER")
    manager_group_names  = optional(set(string), [])
  }))
  default  = {}
  nullable = false
}

variable "monthly_budget_usd" {
  description = "Monthly workspace Databricks list-price budget in USD."
  type        = number
  default     = 10
  nullable    = false
  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than zero."
  }
}

variable "budget_alert_email_addresses" {
  description = "Budget alert recipients. Empty disables budget creation; supplying recipients enables it."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "budget_alert_threshold_percentages" {
  description = "Monthly budget alert percentages; defaults to 50%, 80%, and 100%."
  type        = set(number)
  default     = [50, 80, 100]
  nullable    = false
}
