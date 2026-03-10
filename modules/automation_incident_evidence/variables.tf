variable "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to lambda source directory."
  type        = string
}

variable "enabled" {
  description = "Enable incident evidence collector automation."
  type        = bool
  default     = true
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for notifications."
  type        = string
}

variable "evidence_bucket_name" {
  description = "Optional explicit bucket name for incident evidences."
  type        = string
  default     = null
}

variable "evidence_prefix" {
  description = "Prefix path used in evidence bucket."
  type        = string
  default     = "incident-evidence"
}

variable "target_group_arns" {
  description = "Target groups evaluated in evidence collection."
  type        = list(string)
  default     = []
}

variable "log_group_names" {
  description = "CloudWatch log groups queried for recent events."
  type        = list(string)
  default     = []
}

variable "ecs_cluster_arns" {
  description = "Optional ECS clusters to inspect for service events."
  type        = list(string)
  default     = []
}

variable "eks_cluster_names" {
  description = "Optional EKS clusters to inspect for updates."
  type        = list(string)
  default     = []
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda memory in MB."
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days."
  type        = number
  default     = 30
}

variable "alarm_event_pattern" {
  description = "EventBridge event pattern for triggering evidence collection."
  type        = any
  default = {
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
    }
  }
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}
