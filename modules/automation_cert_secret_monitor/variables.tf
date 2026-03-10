variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable cert and secrets monitor automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for monitor execution."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for scheduler."
  type        = string
  default     = "UTC"
}

variable "acm_expiry_threshold_days" {
  description = "Alert when ACM certificates expire within this many days."
  type        = number
  default     = 30
}

variable "secret_rotation_threshold_days" {
  description = "Alert when Secrets Manager next rotation date is within this many days."
  type        = number
  default     = 30
}

variable "dry_run" {
  description = "Enable dry run mode."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alerts."
  type        = string
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 300
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 256
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