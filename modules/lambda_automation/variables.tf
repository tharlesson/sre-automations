variable "name" {
  description = "Lambda function name."
  type        = string
}

variable "description" {
  description = "Lambda function description."
  type        = string
  default     = null
}

variable "source_dir" {
  description = "Directory containing lambda source code."
  type        = string
}

variable "handler" {
  description = "Lambda handler."
  type        = string
}

variable "runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "memory_size" {
  description = "Memory size in MB."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 300
}

variable "environment_variables" {
  description = "Environment variables for lambda."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days."
  type        = number
  default     = 30
}

variable "iam_policy_json" {
  description = "Inline IAM policy JSON attached to execution role."
  type        = string
}

variable "lambda_role_name" {
  description = "Optional custom role name."
  type        = string
  default     = null
}

variable "architectures" {
  description = "Lambda instruction set architectures."
  type        = list(string)
  default     = ["x86_64"]
}

variable "layers" {
  description = "Lambda layer ARNs."
  type        = list(string)
  default     = []
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrent executions for lambda."
  type        = number
  default     = null
}

variable "kms_key_arn" {
  description = "Optional KMS key ARN to encrypt lambda env vars."
  type        = string
  default     = null
}

variable "dlq_enabled" {
  description = "Create/use dead letter queue for lambda async invocations."
  type        = bool
  default     = true
}

variable "dead_letter_target_arn" {
  description = "Optional existing DLQ ARN."
  type        = string
  default     = null
}

variable "dlq_kms_key_id" {
  description = "Optional KMS key ID for created DLQ."
  type        = string
  default     = null
}

variable "max_event_age_seconds" {
  description = "Maximum age of the request for asynchronous invocation."
  type        = number
  default     = 3600
}

variable "max_retry_attempts" {
  description = "Maximum retry attempts for asynchronous invocation."
  type        = number
  default     = 2
}

variable "publish" {
  description = "Whether to publish creation/change as a new Lambda function version."
  type        = bool
  default     = false
}

variable "tracing_mode" {
  description = "Lambda tracing mode: Active or PassThrough."
  type        = string
  default     = "PassThrough"

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing_mode)
    error_message = "tracing_mode must be Active or PassThrough."
  }
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}