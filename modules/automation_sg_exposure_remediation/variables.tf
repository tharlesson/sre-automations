variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "stepfunction_definition_path" {
  description = "Path to ASL template file used by SG remediation workflow."
  type        = string
}

variable "enabled" {
  description = "Enable SG exposure remediation resources."
  type        = bool
  default     = true
}

variable "schedule_expression" {
  description = "Schedule expression used to trigger detection/remediation workflow."
  type        = string
  default     = "cron(0 9 * * ? *)"
}

variable "schedule_timezone" {
  description = "Timezone used for the schedule."
  type        = string
  default     = "UTC"
}

variable "critical_ports" {
  description = "Ports treated as critical when exposed to 0.0.0.0/0 or ::/0."
  type        = list(number)
  default     = [22, 3389, 3306, 5432]
}

variable "exclude_security_group_ids" {
  description = "Security group IDs excluded from checks/remediation."
  type        = list(string)
  default     = []
}

variable "allow_auto_remediation" {
  description = "Allow workflow to execute ingress remediation."
  type        = bool
  default     = false
}

variable "require_manual_approval" {
  description = "Require approved=true in workflow input before remediation step."
  type        = bool
  default     = true
}

variable "dry_run" {
  description = "When true, remediation step only reports intended changes."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for security notifications."
  type        = string
}

variable "approval_sns_topic_arn" {
  description = "Optional SNS topic ARN dedicated to approval requests."
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
