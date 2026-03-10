variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable SSM runbooks automation resources."
  type        = bool
  default     = true
}

variable "enable_patching_schedule" {
  description = "Enable scheduled patching execution window."
  type        = bool
  default     = true
}

variable "enable_runbook_schedule" {
  description = "Enable scheduled operational runbook execution window."
  type        = bool
  default     = true
}

variable "patching_schedule_expression" {
  description = "Schedule expression used for patching window."
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "runbook_schedule_expression" {
  description = "Schedule expression used for operational runbook window."
  type        = string
  default     = "cron(0 3 ? * MON-FRI *)"
}

variable "schedule_timezone" {
  description = "Timezone used in EventBridge Scheduler."
  type        = string
  default     = "UTC"
}

variable "patching_document_name" {
  description = "SSM document name used for patching operation."
  type        = string
}

variable "runbook_document_name" {
  description = "SSM document name used for routine runbook execution."
  type        = string
}

variable "target_tag_selector" {
  description = "Tag selector used to choose EC2 targets for SSM commands."
  type        = map(string)
  default = {
    Schedule = "office-hours"
  }
}

variable "patch_operation" {
  description = "Patching operation mode (typically Scan or Install)."
  type        = string
  default     = "Scan"
}

variable "runbook_parameters" {
  description = "Parameters passed to the scheduled runbook document."
  type        = map(list(string))
  default     = {}
}

variable "require_manual_approval" {
  description = "Require explicit approved=true input before sending SSM command."
  type        = bool
  default     = false
}

variable "dry_run" {
  description = "When true, no SSM command is sent."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for execution notifications."
  type        = string
}

variable "approval_sns_topic_arn" {
  description = "Optional SNS topic ARN used for manual approval requests."
  type        = string
  default     = null
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