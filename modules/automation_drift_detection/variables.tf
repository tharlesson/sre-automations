variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable operational drift detection automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for drift detection runs."
  type        = string
  default     = "cron(0 11 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone used by scheduler."
  type        = string
  default     = "UTC"
}

variable "storage_bucket_name" {
  description = "Optional existing bucket used for baseline and drift reports."
  type        = string
  default     = null
}

variable "baseline_object_key" {
  description = "S3 key containing expected baseline JSON."
  type        = string
  default     = "drift/baseline.json"
}

variable "publish_initial_baseline" {
  description = "Publish initial baseline object content to baseline_object_key."
  type        = bool
  default     = false
}

variable "initial_baseline_content" {
  description = "Optional JSON content used when publish_initial_baseline=true."
  type        = string
  default     = null
}

variable "report_prefix" {
  description = "S3 prefix used to store drift reports."
  type        = string
  default     = "drift-reports"
}

variable "sns_topic_arn" {
  description = "Optional SNS topic ARN for drift alerts."
  type        = string
  default     = null
}

variable "dry_run" {
  description = "When true, report is generated but not stored in S3."
  type        = bool
  default     = false
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
