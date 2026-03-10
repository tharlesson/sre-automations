variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "stepfunction_definition_path" {
  description = "Path to ASL template used by rollback workflow."
  type        = string
}

variable "enabled" {
  description = "Enable ECS rollback workflow resources."
  type        = bool
  default     = true
}

variable "enable_event_trigger" {
  description = "Create EventBridge trigger for ECS deployment failures."
  type        = bool
  default     = false
}

variable "ecs_deployment_failure_pattern" {
  description = "Event pattern used when enable_event_trigger=true."
  type        = any
  default = {
    source      = ["aws.ecs"]
    detail-type = ["ECS Deployment State Change"]
    detail = {
      eventType = ["ERROR"]
    }
  }
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for rollback notifications."
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
