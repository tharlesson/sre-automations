variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable approval bridge resources."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN carrying approval events."
  type        = string
}

variable "chatops_webhook_url" {
  description = "Optional ChatOps webhook URL (Slack/Teams) for approval notifications."
  type        = string
  default     = null
}

variable "itsm_webhook_url" {
  description = "Optional ITSM webhook URL for approval notifications."
  type        = string
  default     = null
}

variable "forward_only_approval_messages" {
  description = "Forward only messages containing approval semantics."
  type        = bool
  default     = true
}

variable "http_timeout_seconds" {
  description = "HTTP timeout in seconds for webhook calls."
  type        = number
  default     = 10
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 128
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