variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "stepfunction_definition_path" {
  description = "Path to ASL template used by backup validation workflow."
  type        = string
}

variable "enabled" {
  description = "Enable backup validation workflow automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for workflow execution."
  type        = string
  default     = "cron(0 4 ? * SUN *)"
}

variable "schedule_timezone" {
  description = "Timezone for scheduler."
  type        = string
  default     = "UTC"
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for backup validation notifications."
  type        = string
}

variable "evidence_bucket_name" {
  description = "Optional explicit bucket name to store validation evidences."
  type        = string
  default     = null
}

variable "evidence_prefix" {
  description = "Evidence prefix inside the bucket."
  type        = string
  default     = "backup-validation"
}

variable "snapshot_max_age_days" {
  description = "Maximum acceptable age for latest snapshot."
  type        = number
  default     = 7
}

variable "dry_run" {
  description = "When true, restore operations are simulated only."
  type        = bool
  default     = true
}

variable "allow_restore" {
  description = "Explicit flag to allow creating temporary restore resources."
  type        = bool
  default     = false

  validation {
    condition     = var.dry_run || var.allow_restore
    error_message = "When dry_run=false, allow_restore must be true."
  }
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 1024
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
