variable "region" {
  description = "AWS region."
  type        = string
}

variable "aws_profile" {
  description = "Optional AWS CLI profile."
  type        = string
  default     = null
}

variable "aws_assume_role_arn" {
  description = "Optional IAM Role ARN to assume in target AWS account."
  type        = string
  default     = null
}

variable "aws_assume_role_session_name" {
  description = "Session name used when assuming role."
  type        = string
  default     = "terraform-environment-scheduler"
}

variable "client" {
  description = "Client identifier for naming and tags."
  type        = string
}

variable "environment" {
  description = "Environment identifier (dev, stg, prod)."
  type        = string
}

variable "application" {
  description = "Application/workload identifier used in names."
  type        = string
  default     = "environment-scheduler"
}

variable "state_bucket_name" {
  description = "Optional explicit S3 bucket name for environment state. If null, a name is auto-generated."
  type        = string
  default     = null
}

variable "state_object_key" {
  description = "S3 object key used to store ECS/EKS state."
  type        = string
  default     = "environment-scheduler/state.json"
}

variable "state_bucket_force_destroy" {
  description = "Allow Terraform to destroy the state bucket with objects."
  type        = bool
  default     = false
}

variable "state_access_log_bucket_name" {
  description = "Optional S3 bucket name for server access logs. If null, uses the state bucket itself."
  type        = string
  default     = null
}

variable "state_access_log_prefix" {
  description = "Prefix used for state bucket server access logs."
  type        = string
  default     = "server-access-logs/"
}

variable "state_bucket_sse_algorithm" {
  description = "Bucket encryption algorithm (AES256 or aws:kms)."
  type        = string
  default     = "AES256"
}

variable "state_bucket_kms_key_arn" {
  description = "Optional KMS key ARN for state bucket encryption when using aws:kms."
  type        = string
  default     = null
}

variable "state_bucket_lifecycle_current_days" {
  description = "Optional expiration in days for current state object versions."
  type        = number
  default     = null
}

variable "state_bucket_lifecycle_noncurrent_days" {
  description = "Optional expiration in days for non-current state object versions."
  type        = number
  default     = null
}

variable "lambda_runtime" {
  description = "Lambda runtime."
  type        = string
  default     = "python3.12"
}

variable "lambda_handler" {
  description = "Lambda handler."
  type        = string
  default     = "handler.lambda_handler"
}

variable "lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 900
}

variable "lambda_memory_size" {
  description = "Lambda memory size in MB."
  type        = number
  default     = 512
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}

variable "log_level" {
  description = "Application log level."
  type        = string
  default     = "INFO"
}

variable "dry_run" {
  description = "When true, Lambda logs intended actions without changing resources."
  type        = bool
  default     = false
}

variable "restore_delay_seconds" {
  description = "Delay after start action before restoring ECS/EKS desired counts."
  type        = number
  default     = 60
}

variable "eks_excluded_namespaces" {
  description = "Kubernetes namespaces excluded from EKS scale operations."
  type        = list(string)
  default     = ["kube-system", "kube-public", "kube-node-lease"]
}

variable "schedule_timezone" {
  description = "Timezone used by AWS Scheduler."
  type        = string
  default     = "America/Sao_Paulo"
}

variable "start_schedule_expression" {
  description = "Cron/rate expression for start action."
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "stop_schedule_expression" {
  description = "Cron/rate expression for stop action."
  type        = string
  default     = "cron(0 20 ? * MON-FRI *)"
}

variable "scheduler_state" {
  description = "Scheduler state."
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.scheduler_state)
    error_message = "scheduler_state must be ENABLED or DISABLED."
  }
}

variable "tags" {
  description = "Common tags."
  type        = map(string)
  default     = {}
}
