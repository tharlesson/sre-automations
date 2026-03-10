variable "project" {
  description = "Project identifier used for naming."
  type        = string
}

variable "environment" {
  description = "Environment name (dev, stage, prod)."
  type        = string
}

variable "region" {
  description = "AWS region code."
  type        = string
}

variable "application" {
  description = "Application identifier for mandatory tag Application."
  type        = string
}

variable "owner" {
  description = "Owner tag value."
  type        = string
}

variable "cost_center" {
  description = "CostCenter tag value."
  type        = string
}

variable "managed_by" {
  description = "ManagedBy tag value."
  type        = string
  default     = "Terraform"
}

variable "extra_tags" {
  description = "Additional tags merged over mandatory tags."
  type        = map(string)
  default     = {}
}