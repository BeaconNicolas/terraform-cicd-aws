variable "project" {
  description = "Short project name used as a prefix for every resource. The pipeline sets it with TF_VAR_project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.project))
    error_message = "project must be 2-12 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name. The pipeline sets it with TF_VAR_environment."
  type        = string

  validation {
    condition     = contains(["dev", "int", "prod"], var.environment)
    error_message = "environment must be one of dev, int or prod."
  }
}

variable "aws_region" {
  description = "AWS region to deploy into. The pipeline sets it with TF_VAR_aws_region."
  type        = string
}

variable "app_message" {
  description = "Example application setting stored in SSM Parameter Store."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep old object versions in the example bucket before they expire."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1
    error_message = "noncurrent_version_retention_days must be at least 1."
  }
}

variable "force_destroy" {
  description = "Allow terraform destroy to delete the example bucket even if it holds objects. Used at teardown."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags for every resource."
  type        = map(string)
  default     = {}
}
