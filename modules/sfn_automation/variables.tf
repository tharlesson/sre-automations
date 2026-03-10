variable "name" {
  description = "State machine name."
  type        = string
}

variable "definition_path" {
  description = "Path to ASL JSON template file."
  type        = string
}

variable "definition_vars" {
  description = "Variables injected in ASL template."
  type        = map(any)
  default     = {}
}

variable "state_machine_type" {
  description = "State machine type."
  type        = string
  default     = "STANDARD"

  validation {
    condition     = contains(["STANDARD", "EXPRESS"], var.state_machine_type)
    error_message = "state_machine_type must be STANDARD or EXPRESS."
  }
}

variable "iam_policy_json" {
  description = "Inline IAM policy JSON attached to state machine role."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch logs retention in days."
  type        = number
  default     = 30
}

variable "tracing_enabled" {
  description = "Enable X-Ray tracing."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply."
  type        = map(string)
  default     = {}
}