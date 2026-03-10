variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable scheduler automation."
  type        = bool
  default     = true
}

variable "start_schedule_expression" {
  description = "Schedule expression for start action."
  type        = string
}

variable "stop_schedule_expression" {
  description = "Schedule expression for stop action."
  type        = string
}

variable "schedule_timezone" {
  description = "Timezone for EventBridge Scheduler."
  type        = string
  default     = "UTC"
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

variable "dry_run" {
  description = "When true, no mutating action is executed."
  type        = bool
  default     = true
}

variable "tag_selector" {
  description = "Resource tag selectors used to scope resources."
  type        = map(string)
  default = {
    Schedule = "office-hours"
  }
}

variable "ec2_pre_stop_ssm_document" {
  description = "Optional SSM document to execute before stopping EC2."
  type        = string
  default     = null
}

variable "ec2_pre_stop_ssm_timeout_seconds" {
  description = "Timeout for SSM pre-stop command."
  type        = number
  default     = 600
}

variable "state_bucket_name" {
  description = "Optional explicit S3 bucket name used for scheduler state."
  type        = string
  default     = null
}

variable "state_object_key" {
  description = "S3 object key for persisted scheduler state."
  type        = string
  default     = "scheduler/state.json"
}

variable "state_bucket_force_destroy" {
  description = "Allow destroying bucket with objects."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}