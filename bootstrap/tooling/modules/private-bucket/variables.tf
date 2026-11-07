variable "name" {
  description = "Globally unique bucket name."
  type        = string
}

variable "force_destroy" {
  description = "Let terraform destroy delete the bucket even when it still holds objects and versions."
  type        = bool
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for default encryption. null means SSE-S3, which has no idle cost."
  type        = string
  default     = null
}

variable "policy_statements" {
  description = "Extra bucket policy statements, added after the statement that denies plain HTTP."
  type        = any
  default     = []
}

variable "noncurrent_version_expiration_days" {
  description = "Days before old object versions are deleted."
  type        = number
  default     = 30
}

variable "current_version_expiration_days" {
  description = "Days before current objects expire. null keeps them."
  type        = number
  default     = null
}

variable "eventbridge_notifications" {
  description = "Send object events to Amazon EventBridge."
  type        = bool
  default     = false
}
