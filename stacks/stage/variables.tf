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

variable "enable_ssm_runbooks_automation" {
  description = "Enable P1 SSM patching/runbooks automation."
  type        = bool
  default     = true
}

variable "ssm_patching_schedule_expression" {
  description = "Schedule expression for SSM patching window."
  type        = string
  default     = "cron(0 2 ? * SUN *)"
}

variable "ssm_runbook_schedule_expression" {
  description = "Schedule expression for SSM operational runbook window."
  type        = string
  default     = "cron(0 3 ? * MON-FRI *)"
}

variable "ssm_runbook_target_tag_selector" {
  description = "Tag selector used by SSM runbooks automation."
  type        = map(string)
  default = {
    Schedule = "office-hours"
  }
}

variable "ssm_runbook_patch_operation" {
  description = "Patching operation mode (Scan or Install)."
  type        = string
  default     = "Scan"
}

variable "ssm_runbook_parameters" {
  description = "Parameters passed to the scheduled operational runbook."
  type        = map(list(string))
  default     = {}
}

variable "ssm_runbook_require_manual_approval" {
  description = "Require manual approval before dispatching SSM commands."
  type        = bool
  default     = false
}

variable "ssm_runbook_dry_run" {
  description = "Run SSM runbooks automation in dry-run mode."
  type        = bool
  default     = true
}

variable "ssm_patching_document_name" {
  description = "Optional patching document override."
  type        = string
  default     = null
}

variable "ssm_operational_document_name" {
  description = "Optional operational runbook document override."
  type        = string
  default     = null
}

variable "ssm_runbook_approval_sns_topic_arn" {
  description = "Optional SNS topic for manual approval requests."
  type        = string
  default     = null
}

variable "automation_alert_email_endpoints" {
  description = "Optional list of email endpoints subscribed to SNS automation alerts topic."
  type        = list(string)
  default     = []
}

variable "approval_alert_email_endpoints" {
  description = "Optional list of email endpoints subscribed to SNS approval requests topic."
  type        = list(string)
  default     = []
}

variable "enable_approval_bridge" {
  description = "Enable webhook bridge for approval requests (ChatOps/ITSM)."
  type        = bool
  default     = true
}

variable "approval_bridge_chatops_webhook_url" {
  description = "Optional ChatOps webhook URL for approval notifications."
  type        = string
  default     = null
}

variable "approval_bridge_itsm_webhook_url" {
  description = "Optional ITSM webhook URL for approval notifications."
  type        = string
  default     = null
}

variable "approval_bridge_forward_only_approval_messages" {
  description = "Forward only approval-like messages to webhooks."
  type        = bool
  default     = true
}

variable "approval_bridge_http_timeout_seconds" {
  description = "HTTP timeout for approval bridge webhook posts."
  type        = number
  default     = 10
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

variable "enable_sg_exposure_remediation" {
  description = "Enable P1 security group exposure remediation automation."
  type        = bool
  default     = true
}

variable "sg_remediation_schedule_expression" {
  description = "Schedule expression for SG exposure remediation workflow."
  type        = string
  default     = "cron(0 9 * * ? *)"
}

variable "sg_remediation_critical_ports" {
  description = "Critical ports considered exposed when open to the internet."
  type        = list(number)
  default     = [22, 3389, 3306, 5432]
}

variable "sg_remediation_excluded_security_group_ids" {
  description = "Security groups excluded from SG remediation checks."
  type        = list(string)
  default     = []
}

variable "sg_remediation_allow_auto_remediation" {
  description = "Allow SG workflow to revoke risky ingress rules."
  type        = bool
  default     = false
}

variable "sg_remediation_require_manual_approval" {
  description = "Require approved=true execution input before SG remediation."
  type        = bool
  default     = true
}

variable "sg_remediation_dry_run" {
  description = "Run SG remediation workflow in dry-run mode."
  type        = bool
  default     = true
}

variable "sg_remediation_approval_sns_topic_arn" {
  description = "Optional SNS topic ARN dedicated to SG remediation approval requests."
  type        = string
  default     = null
}

variable "enable_finops_report" {
  description = "Enable P1 FinOps reporting automation."
  type        = bool
  default     = true
}

variable "finops_report_schedule_expression" {
  description = "Schedule expression for FinOps report generation."
  type        = string
  default     = "cron(0 10 ? * MON *)"
}

variable "finops_report_bucket_name" {
  description = "Optional existing S3 bucket for FinOps reports."
  type        = string
  default     = null
}

variable "finops_report_prefix" {
  description = "Prefix used in S3 for FinOps report objects."
  type        = string
  default     = "finops-reports"
}

variable "finops_report_lookback_days" {
  description = "Lookback period used to aggregate FinOps costs."
  type        = number
  default     = 30
}

variable "finops_report_group_by_tag_keys" {
  description = "Tag keys used in FinOps grouped views."
  type        = list(string)
  default     = ["Environment", "Application", "CostCenter"]
}

variable "finops_include_savings_plans_analysis" {
  description = "Include Savings Plans utilization analysis in FinOps report."
  type        = bool
  default     = true
}

variable "finops_include_reservation_analysis" {
  description = "Include RI utilization analysis in FinOps report."
  type        = bool
  default     = true
}

variable "finops_include_rightsizing_analysis" {
  description = "Include Compute Optimizer rightsizing recommendations in FinOps report."
  type        = bool
  default     = true
}

variable "finops_rightsizing_max_results" {
  description = "Maximum rightsizing recommendations in FinOps report."
  type        = number
  default     = 50
}

variable "finops_report_dry_run" {
  description = "Generate FinOps report without persisting in S3."
  type        = bool
  default     = false
}

variable "enable_drift_detection" {
  description = "Enable P1 operational drift detection automation."
  type        = bool
  default     = true
}

variable "drift_detection_schedule_expression" {
  description = "Schedule expression for drift detection."
  type        = string
  default     = "cron(0 11 * * ? *)"
}

variable "drift_detection_storage_bucket_name" {
  description = "Optional existing S3 bucket for baseline and drift reports."
  type        = string
  default     = null
}

variable "drift_detection_baseline_object_key" {
  description = "S3 key of baseline JSON used by drift detection."
  type        = string
  default     = "drift/baseline.json"
}

variable "drift_detection_publish_initial_baseline" {
  description = "Publish initial baseline object content to S3 baseline key."
  type        = bool
  default     = false
}

variable "drift_detection_initial_baseline_file_path" {
  description = "Optional local file path containing baseline JSON for initial seed."
  type        = string
  default     = null
}

variable "drift_detection_report_prefix" {
  description = "S3 prefix used to store drift reports."
  type        = string
  default     = "drift-reports"
}

variable "drift_detection_dry_run" {
  description = "Run drift detection without persisting report in S3."
  type        = bool
  default     = false
}

variable "enable_observability_alarms" {
  description = "Enable baseline Lambda and Step Functions failure alarms."
  type        = bool
  default     = true
}
