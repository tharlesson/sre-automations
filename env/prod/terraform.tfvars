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

schedule_timezone                = "America/Sao_Paulo"
log_retention_days               = 60
automation_alert_email_endpoints = ["sre-prod@example.com"]

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

enable_observability_alarms = true
enable_ssm_documents        = true