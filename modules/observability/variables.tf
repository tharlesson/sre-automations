variable "name_prefix" {
  description = "Prefix used for alarm names."
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for alarm notifications."
  type        = string
}

variable "enabled" {
  description = "Enable alarm creation."
  type        = bool
  default     = true
}

variable "lambda_function_names" {
  description = "Lambda function names to monitor."
  type        = list(string)
  default     = []
}

variable "state_machine_arns" {
  description = "Step Function ARNs to monitor."
  type        = list(string)
  default     = []
}

variable "period_seconds" {
  description = "Alarm evaluation period in seconds."
  type        = number
  default     = 300
}

variable "evaluation_periods" {
  description = "How many periods to evaluate."
  type        = number
  default     = 1
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}