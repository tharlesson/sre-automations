variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable FinOps reporting automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for FinOps reports."
  type        = string
  default     = "cron(0 10 ? * MON *)"
}

variable "schedule_timezone" {
  description = "Timezone used for scheduler."
  type        = string
  default     = "UTC"
}

variable "report_bucket_name" {
  description = "Optional existing bucket used to store FinOps reports."
  type        = string
  default     = null
}

variable "report_prefix" {
  description = "Prefix path used for report files in S3."
  type        = string
  default     = "finops-reports"
}

variable "lookback_days" {
  description = "Lookback window (days) for cost aggregation."
  type        = number
  default     = 30
}

variable "group_by_tag_keys" {
  description = "Tag keys used in grouped FinOps views."
  type        = list(string)
  default     = ["Environment", "Application", "CostCenter"]
}

variable "sns_topic_arn" {
  description = "Optional SNS topic ARN for report notifications."
  type        = string
  default     = null
}

variable "dry_run" {
  description = "When true, report is generated but not persisted to S3."
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