variable "project" {
  description = "Short project name used as a prefix for every resource."
  type        = string
  default     = "tfcicd"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.project))
    error_message = "project must be 2-12 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "aws_region" {
  description = "Region for the pipelines, the state bucket and the workload."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repository (github.com)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name, without the owner."
  type        = string
}

variable "environments" {
  description = <<-EOT
    Environments to build a pipeline for. Each key is an environment and branch name.
    account_id is the target account the pipeline deploys into; leave it out to deploy
    into this (tooling) account, which is the single-account setup.
  EOT
  type = map(object({
    account_id = optional(string)
  }))
  default = {
    dev  = {}
    int  = {}
    prod = {}
  }

  validation {
    condition     = length(var.environments) > 0 && alltrue([for k in keys(var.environments) : contains(["dev", "int", "prod"], k)])
    error_message = "environments keys must be some of dev, int and prod."
  }

  validation {
    condition     = alltrue([for v in values(var.environments) : v.account_id == null || can(regex("^[0-9]{12}$", v.account_id))])
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "notification_email" {
  description = "Email address for approval requests and budget alerts. AWS sends a confirmation link first."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "notification_email must be an email address."
  }
}

variable "budget_limit_usd" {
  description = "Monthly cost budget for this account in US dollars. Alerts at 80% actual and 100% forecast."
  type        = number
  default     = 5
}

variable "create_budget" {
  description = "Create the monthly cost budget with email alerts."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Let terraform destroy delete buckets and ECR repositories that still hold data. Set to true before teardown."
  type        = bool
  default     = false
}

variable "create_kms_key" {
  description = "Encrypt buckets and pipeline artifacts with a customer-managed KMS key. Off by default: a key costs about 1 USD a month even when idle."
  type        = bool
  default     = false
}

variable "create_github_oidc_provider" {
  description = "Create the GitHub OIDC identity provider. Set to false if this account already has one for token.actions.githubusercontent.com."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Days to keep CodeBuild logs."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}

variable "codebuild_image" {
  description = "CodeBuild-managed image for the Tools image stage, which runs Docker. The other stages run the tools image from ECR."
  type        = string
  default     = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
}
