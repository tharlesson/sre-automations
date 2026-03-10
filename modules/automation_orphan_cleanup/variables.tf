variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable orphan cleanup automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for cleanup execution."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for scheduler."
  type        = string
  default     = "UTC"
}

variable "snapshot_retention_days" {
  description = "Retention threshold for snapshots."
  type        = number
  default     = 30
}

variable "log_group_retention_days" {
  description = "Retention threshold for orphan log groups."
  type        = number
  default     = 30
}

variable "ecr_image_retention_days" {
  description = "Retention threshold for untagged ECR images."
  type        = number
  default     = 30
}

variable "dry_run" {
  description = "Mandatory dry-run mode for safe reporting."
  type        = bool
  default     = true
}

variable "allow_destructive_actions" {
  description = "Explicit flag required to execute deletions when dry_run=false."
  type        = bool
  default     = false

  validation {
    condition     = var.dry_run || var.allow_destructive_actions
    error_message = "When dry_run=false, allow_destructive_actions must be true."
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for report notifications."
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
