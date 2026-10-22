variable "name" {
  description = "Display name of the monthly Databricks budget."
  type        = string
  nullable    = false
  validation {
    condition     = length(trimspace(var.name)) > 0 && var.name == trimspace(var.name)
    error_message = "name must be non-empty without surrounding whitespace."
  }
}

variable "monthly_limit_usd" {
  description = "Monthly Databricks list-price budget in USD; this is an alert threshold, not a spending cap."
  type        = number
  default     = 10
  nullable    = false
  validation {
    condition     = var.monthly_limit_usd > 0
    error_message = "monthly_limit_usd must be greater than zero."
  }
}

variable "workspace_ids" {
  description = "Workspace IDs included in this budget. Empty means all workspaces in the account."
  type        = set(number)
  default     = []
  nullable    = false
  validation {
    condition     = alltrue([for id in var.workspace_ids : id > 0 && floor(id) == id])
    error_message = "workspace_ids must contain positive integers."
  }
}

variable "alert_email_addresses" {
  description = "Email recipients for every budget threshold; at least one recipient is required."
  type        = set(string)
  nullable    = false
  validation {
    condition     = length(var.alert_email_addresses) > 0 && alltrue([for email in var.alert_email_addresses : can(regex("^[^ @]+@[^ @]+[.][^ @]+$", email)) && email == trimspace(email)])
    error_message = "Provide at least one valid email address without surrounding whitespace."
  }
}

variable "alert_threshold_percentages" {
  description = "One to four unique monthly spending thresholds expressed as percentages of the budget."
  type        = set(number)
  default     = [50, 80, 100]
  nullable    = false
  validation {
    condition     = length(var.alert_threshold_percentages) >= 1 && length(var.alert_threshold_percentages) <= 4 && alltrue([for percent in var.alert_threshold_percentages : percent > 0])
    error_message = "Provide one to four positive threshold percentages."
  }
}
