variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable tag auditor automation."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression for tag audit."
  type        = string
  default     = "cron(0 7 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone for scheduler."
  type        = string
  default     = "UTC"
}

variable "required_tags" {
  description = "Mandatory tags that must exist on resources."
  type        = list(string)
  default     = ["Environment", "Application", "Owner", "CostCenter", "ManagedBy"]
}

variable "default_tag_values" {
  description = "Default tag values used for optional auto-remediation."
  type        = map(string)
  default     = {}
}

variable "dry_run" {
  description = "Enable dry run mode."
  type        = bool
  default     = true
}

variable "auto_remediate" {
  description = "Enable automatic remediation by tagging resources."
  type        = bool
  default     = false
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