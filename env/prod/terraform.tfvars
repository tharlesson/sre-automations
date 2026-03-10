region      = "us-east-1"
aws_profile = "my-prod-profile"

project     = "sreauto"
environment = "prod"
application = "sre-platform"
owner       = "platform-team"
cost_center = "cc-1234"
managed_by  = "Terraform"

extra_tags = {
  Team = "SRE"
}

schedule_timezone                              = "America/Sao_Paulo"
log_retention_days                             = 60
automation_alert_email_endpoints               = ["sre-prod@example.com"]
approval_alert_email_endpoints                 = []
enable_approval_bridge                         = true
approval_bridge_chatops_webhook_url            = null
approval_bridge_itsm_webhook_url               = null
approval_bridge_forward_only_approval_messages = true
approval_bridge_http_timeout_seconds           = 10

enable_scheduler                    = false
scheduler_dry_run                   = true
scheduler_start_schedule_expression = "cron(0 7 ? * MON-FRI *)"
scheduler_stop_schedule_expression  = "cron(0 22 ? * MON-FRI *)"
scheduler_tag_selector = {
  Environment = "prod"
  Schedule    = "office-hours"
}
scheduler_ec2_pre_stop_ssm_document = null

enable_tag_auditor              = true
tag_auditor_dry_run             = false
tag_auditor_auto_remediate      = false
tag_auditor_schedule_expression = "cron(0 5 * * ? *)"
tag_auditor_default_tag_values = {
  ManagedBy = "Terraform"
}

enable_cert_secret_monitor              = true
cert_secret_monitor_dry_run             = false
cert_secret_monitor_schedule_expression = "cron(0 6 * * ? *)"
acm_expiry_threshold_days               = 30
secret_rotation_threshold_days          = 20

enable_orphan_cleanup                    = true
orphan_cleanup_dry_run                   = true
orphan_cleanup_allow_destructive_actions = false
orphan_cleanup_schedule_expression       = "cron(0 1 * * ? *)"
orphan_cleanup_snapshot_retention_days   = 45
orphan_cleanup_log_group_retention_days  = 45
orphan_cleanup_ecr_image_retention_days  = 45

enable_incident_evidence            = true
incident_evidence_target_group_arns = []
incident_evidence_log_group_names = [
  "/aws/lambda/example-service-prod"
]
incident_evidence_ecs_cluster_arns  = []
incident_evidence_eks_cluster_names = []

enable_ecs_rollback               = true
enable_ecs_rollback_event_trigger = true

enable_backup_validation                = true
backup_validation_dry_run               = true
backup_validation_allow_restore         = false
backup_validation_schedule_expression   = "cron(0 2 ? * SUN *)"
backup_validation_snapshot_max_age_days = 3

enable_ssm_runbooks_automation   = true
ssm_patching_schedule_expression = "cron(0 1 ? * SUN *)"
ssm_runbook_schedule_expression  = "cron(0 2 ? * MON-FRI *)"
ssm_runbook_target_tag_selector = {
  Environment = "prod"
  Schedule    = "office-hours"
}
ssm_runbook_patch_operation         = "Scan"
ssm_runbook_parameters              = {}
ssm_runbook_require_manual_approval = true
ssm_runbook_dry_run                 = false
ssm_patching_document_name          = null
ssm_operational_document_name       = null
ssm_runbook_approval_sns_topic_arn  = null

enable_sg_exposure_remediation             = true
sg_remediation_schedule_expression         = "cron(0 8 * * ? *)"
sg_remediation_critical_ports              = [22, 3389, 3306, 5432]
sg_remediation_excluded_security_group_ids = []
sg_remediation_allow_auto_remediation      = false
sg_remediation_require_manual_approval     = true
sg_remediation_dry_run                     = true
sg_remediation_approval_sns_topic_arn      = null

enable_finops_report                  = true
finops_report_schedule_expression     = "cron(0 9 ? * MON *)"
finops_report_bucket_name             = null
finops_report_prefix                  = "finops-reports"
finops_report_lookback_days           = 30
finops_report_group_by_tag_keys       = ["Environment", "Application", "CostCenter"]
finops_include_savings_plans_analysis = true
finops_include_reservation_analysis   = true
finops_include_rightsizing_analysis   = true
finops_rightsizing_max_results        = 100
finops_report_dry_run                 = false

enable_drift_detection                     = true
drift_detection_schedule_expression        = "cron(0 10 * * ? *)"
drift_detection_storage_bucket_name        = null
drift_detection_baseline_object_key        = "drift/baseline.json"
drift_detection_publish_initial_baseline   = false
drift_detection_initial_baseline_file_path = null
drift_detection_report_prefix              = "drift-reports"
drift_detection_dry_run                    = false

enable_observability_alarms = true
enable_ssm_documents        = true
