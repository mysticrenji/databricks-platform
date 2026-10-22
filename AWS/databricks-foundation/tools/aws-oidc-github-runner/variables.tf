variable "aws_region" {
  description = "AWS region used by the provider."
  type        = string
}

variable "role_name" {
  description = "Name for the IAM role GitHub Actions assumes."
  type        = string
  default     = "github-actions-oidc"
}

variable "github_subjects" {
  description = <<-EOT
    Allowed GitHub OIDC subject claims. Prefer one of:
    repo:OWNER/REPOSITORY:ref:refs/heads/BRANCH
    repo:OWNER/REPOSITORY:environment:ENVIRONMENT

    Repositories created after 2026-07-15 use immutable subject claims:
    repo:OWNER@OWNER_ID/REPOSITORY@REPOSITORY_ID:ref:refs/heads/BRANCH
  EOT
  type        = set(string)

  validation {
    condition     = length(var.github_subjects) > 0 && alltrue([for subject in var.github_subjects : can(regex("^repo:[^/@:]+(@[0-9]+)?/[^/@:]+(@[0-9]+)?:(ref:refs/heads/[^:]+|environment:[^:]+)$", subject))])
    error_message = "Each github_subjects entry must restrict access to a repository branch or GitHub environment, using optional immutable owner and repository IDs."
  }
}

variable "managed_policy_arns" {
  description = "Managed IAM policies to attach to the GitHub Actions role. Supply least-privilege policies."
  type        = set(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline IAM policy names to JSON policy documents."
  type        = map(string)
  default     = {}
}

variable "max_session_duration" {
  description = "Maximum OIDC role session duration, in seconds."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 and 43200 seconds."
  }
}

variable "tags" {
  description = "Tags applied to created AWS resources."
  type        = map(string)
  default     = {}
}
