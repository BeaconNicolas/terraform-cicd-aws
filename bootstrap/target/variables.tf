variable "project" {
  description = "Same project name as in bootstrap/tooling."
  type        = string
  default     = "tfcicd"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.project))
    error_message = "project must be 2-12 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "Same region as in bootstrap/tooling. The workload is deployed here."
  type        = string
}

variable "environments" {
  description = "Environments this account hosts. Single account: all of them. See the target_accounts output of bootstrap/tooling."
  type        = set(string)
  default     = ["dev", "int", "prod"]

  validation {
    condition     = length(var.environments) > 0 && alltrue([for e in var.environments : contains(["dev", "int", "prod"], e)])
    error_message = "environments must be some of dev, int and prod."
  }
}

variable "tooling_account_id" {
  description = "Account that runs the pipelines (tooling_account_id output of bootstrap/tooling). null means this account."
  type        = string
  default     = null

  validation {
    condition     = var.tooling_account_id == null || can(regex("^[0-9]{12}$", var.tooling_account_id))
    error_message = "tooling_account_id must be a 12-digit AWS account ID."
  }
}

variable "state_bucket" {
  description = "Terraform state bucket (state_bucket output of bootstrap/tooling)."
  type        = string
}

variable "state_kms_key_arn" {
  description = "kms_key_arn output of bootstrap/tooling when it uses a KMS key; otherwise null."
  type        = string
  default     = null
}

variable "create_budget" {
  description = "Create a monthly cost budget in this account. Leave false when this is also the tooling account, which has one already."
  type        = bool
  default     = false
}

variable "budget_limit_usd" {
  description = "Monthly cost budget for this account in US dollars."
  type        = number
  default     = 5
}

variable "notification_email" {
  description = "Email for budget alerts. Needed only when create_budget is true."
  type        = string
  default     = null
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}
