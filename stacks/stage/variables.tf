variable "region" {
  description = "AWS region."
  type        = string
}

variable "aws_profile" {
  description = "Optional AWS profile."
  type        = string
  default     = null
}

variable "aws_assume_role_arn" {
  description = "Optional IAM Role ARN for cross-account deployment."
  type        = string
  default     = null
}

variable "aws_assume_role_session_name" {
  description = "Session name used when assuming role."
  type        = string
  default     = "terraform-sre-automation"
}

variable "project" {
  description = "Project identifier used for naming."
  type        = string
}

variable "environment" {
  description = "Environment identifier (dev, stage, prod)."
  type        = string
}

variable "application" {
  description = "Application tag value."
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
  description = "Additional tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "schedule_timezone" {
  description = "Timezone used by EventBridge Scheduler rules."
  type        = string
  default     = "America/Sao_Paulo"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 30
}

variable "enable_ssm_documents" {
  description = "Enable reusable SSM documents deployment."
  type        = bool
  default     = true
}

variable "automation_alert_email_endpoints" {
  description = "Optional list of email endpoints subscribed to SNS automation alerts topic."
  type        = list(string)
  default     = []
}

variable "enable_scheduler" {
  description = "Enable non-prod environment scheduler automation."
  type        = bool
  default     = true
}

variable "scheduler_dry_run" {
  description = "Run scheduler in dry-run mode."
  type        = bool
  default     = true
}

variable "scheduler_start_schedule_expression" {
  description = "Start schedule expression."
  type        = string
  default     = "cron(0 8 ? * MON-FRI *)"
}

variable "scheduler_stop_schedule_expression" {
  description = "Stop schedule expression."
  type        = string
  default     = "cron(0 20 ? * MON-FRI *)"
}

variable "scheduler_tag_selector" {
  description = "Tag selector used by scheduler automation."
  type        = map(string)
  default = {
    Schedule = "office-hours"
  }
}

variable "scheduler_ec2_pre_stop_ssm_document" {
  description = "Optional SSM document executed before stopping EC2 instances."
  type        = string
  default     = null
}

variable "enable_tag_auditor" {
  description = "Enable mandatory tags auditor automation."
  type        = bool
  default     = true
}

variable "tag_auditor_dry_run" {
  description = "Run tag auditor in dry-run mode."
  type        = bool
  default     = true
}

variable "tag_auditor_auto_remediate" {
  description = "Enable tag auto-remediation."
  type        = bool
  default     = false
}

variable "tag_auditor_schedule_expression" {
  description = "Schedule expression for tag auditor."
  type        = string
  default     = "cron(0 7 * * ? *)"
}

variable "tag_auditor_required_tags" {
  description = "Mandatory tags enforced by auditor."
  type        = list(string)
  default     = ["Environment", "Application", "Owner", "CostCenter", "ManagedBy"]
}

variable "tag_auditor_default_tag_values" {
  description = "Default values used for auto-remediation when tags are missing."
  type        = map(string)
  default     = {}
}

variable "enable_cert_secret_monitor" {
  description = "Enable certificate and secret monitor automation."
  type        = bool
  default     = true
}

variable "cert_secret_monitor_dry_run" {
  description = "Run cert/secret monitor in dry-run mode."
  type        = bool
  default     = true
}

variable "cert_secret_monitor_schedule_expression" {
  description = "Schedule expression for cert/secret monitor."
  type        = string
  default     = "cron(0 8 * * ? *)"
}

variable "acm_expiry_threshold_days" {
  description = "Alert threshold for ACM certificate expiry."
  type        = number
  default     = 30
}

variable "secret_rotation_threshold_days" {
  description = "Alert threshold for secrets rotation due date."
  type        = number
  default     = 30
}

variable "enable_orphan_cleanup" {
  description = "Enable orphan resource cleanup automation."
  type        = bool
  default     = true
}

variable "orphan_cleanup_dry_run" {
  description = "Run orphan cleanup in dry-run/report mode."
  type        = bool
  default     = true
}

variable "orphan_cleanup_allow_destructive_actions" {
  description = "Allow destructive cleanup actions when dry_run=false."
  type        = bool
  default     = false
}

variable "orphan_cleanup_schedule_expression" {
  description = "Schedule expression for orphan cleanup."
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "orphan_cleanup_snapshot_retention_days" {
  description = "Retention threshold for snapshots."
  type        = number
  default     = 30
}

variable "orphan_cleanup_log_group_retention_days" {
  description = "Retention threshold for log groups."
  type        = number
  default     = 30
}

variable "orphan_cleanup_ecr_image_retention_days" {
  description = "Retention threshold for untagged ECR images."
  type        = number
  default     = 30
}

variable "enable_incident_evidence" {
  description = "Enable incident evidence collector automation."
  type        = bool
  default     = true
}

variable "incident_evidence_target_group_arns" {
  description = "Target groups collected in incident evidence."
  type        = list(string)
  default     = []
}

variable "incident_evidence_log_group_names" {
  description = "Log groups analyzed by incident evidence collector."
  type        = list(string)
  default     = []
}

variable "incident_evidence_ecs_cluster_arns" {
  description = "ECS clusters inspected in incident evidence collector."
  type        = list(string)
  default     = []
}

variable "incident_evidence_eks_cluster_names" {
  description = "EKS clusters inspected in incident evidence collector."
  type        = list(string)
  default     = []
}

variable "enable_ecs_rollback" {
  description = "Enable ECS rollback workflow automation."
  type        = bool
  default     = true
}

variable "enable_ecs_rollback_event_trigger" {
  description = "Create EventBridge trigger for ECS deployment failures."
  type        = bool
  default     = false
}

variable "enable_backup_validation" {
  description = "Enable backup validation workflow automation."
  type        = bool
  default     = true
}

variable "backup_validation_dry_run" {
  description = "Run backup validation in dry-run mode."
  type        = bool
  default     = true
}

variable "backup_validation_allow_restore" {
  description = "Allow temporary restore resources when backup_validation_dry_run=false."
  type        = bool
  default     = false
}

variable "backup_validation_schedule_expression" {
  description = "Schedule expression for backup validation workflow."
  type        = string
  default     = "cron(0 4 ? * SUN *)"
}

variable "backup_validation_snapshot_max_age_days" {
  description = "Max accepted age (days) for latest snapshot."
  type        = number
  default     = 7
}

variable "enable_observability_alarms" {
  description = "Enable baseline Lambda and Step Functions failure alarms."
  type        = bool
  default     = true
}