variable "name" {
  description = "Scheduler name."
  type        = string
}

variable "description" {
  description = "Scheduler description."
  type        = string
  default     = null
}

variable "group_name" {
  description = "Optional existing scheduler group name."
  type        = string
  default     = null
}

variable "schedule_expression" {
  description = "Schedule expression (cron or rate)."
  type        = string
}

variable "schedule_timezone" {
  description = "Timezone for schedule execution."
  type        = string
  default     = "UTC"
}

variable "enabled" {
  description = "Enable/disable schedule."
  type        = bool
  default     = true
}

variable "target_arn" {
  description = "Target ARN for scheduler invocation."
  type        = string
}

variable "target_type" {
  description = "Target type for IAM invoke policy. Supported: lambda, sfn."
  type        = string
  default     = "lambda"

  validation {
    condition     = contains(["lambda", "sfn"], var.target_type)
    error_message = "target_type must be lambda or sfn."
  }
}

variable "target_input" {
  description = "Input payload sent to the target."
  type        = map(any)
  default     = {}
}

variable "create_invoke_role" {
  description = "Create scheduler invoke role."
  type        = bool
  default     = true
}

variable "invoke_role_arn" {
  description = "Existing invoke role ARN used when create_invoke_role=false."
  type        = string
  default     = null
}

variable "maximum_event_age_seconds" {
  description = "Maximum event age in seconds for retry policy."
  type        = number
  default     = 3600
}

variable "maximum_retry_attempts" {
  description = "Maximum retry attempts for scheduler target delivery."
  type        = number
  default     = 2
}

variable "dead_letter_arn" {
  description = "Optional dead letter SQS ARN for scheduler target failures."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}