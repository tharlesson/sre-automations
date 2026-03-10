module "common" {
  source = "../../modules/common"

  project     = var.project
  environment = var.environment
  region      = var.region
  application = var.application
  owner       = var.owner
  cost_center = var.cost_center
  managed_by  = var.managed_by
  extra_tags  = var.extra_tags
}

resource "aws_sns_topic" "automation_alerts" {
  name = "${module.common.name_prefix}-automation-alerts"
  tags = module.common.tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = toset(var.automation_alert_email_endpoints)

  topic_arn = aws_sns_topic.automation_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_ssm_document" "patching" {
  count = var.enable_ssm_documents ? 1 : 0

  name            = "${module.common.name_prefix}-patching"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.root}/../../ssm/documents/patching.yaml")
  tags            = module.common.tags
}

resource "aws_ssm_document" "diagnostics" {
  count = var.enable_ssm_documents ? 1 : 0

  name            = "${module.common.name_prefix}-diagnostics"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.root}/../../ssm/documents/diagnostics.yaml")
  tags            = module.common.tags
}

resource "aws_ssm_document" "cleanup_disk" {
  count = var.enable_ssm_documents ? 1 : 0

  name            = "${module.common.name_prefix}-cleanup-disk"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.root}/../../ssm/documents/cleanup_disk.yaml")
  tags            = module.common.tags
}

resource "aws_ssm_document" "service_restart" {
  count = var.enable_ssm_documents ? 1 : 0

  name            = "${module.common.name_prefix}-service-restart"
  document_type   = "Command"
  document_format = "YAML"
  content         = file("${path.root}/../../ssm/documents/service_restart.yaml")
  tags            = module.common.tags
}

module "ssm_runbooks" {
  count  = var.enable_ssm_runbooks_automation ? 1 : 0
  source = "../../modules/automation_ssm_runbooks"

  name_prefix                  = module.common.name_prefix
  lambda_source_dir            = "${path.root}/../../lambdas/p1_ssm_runbooks"
  enabled                      = true
  enable_patching_schedule     = true
  enable_runbook_schedule      = true
  patching_schedule_expression = var.ssm_patching_schedule_expression
  runbook_schedule_expression  = var.ssm_runbook_schedule_expression
  schedule_timezone            = var.schedule_timezone
  patching_document_name       = coalesce(var.ssm_patching_document_name, try(aws_ssm_document.patching[0].name, "AWS-RunPatchBaseline"))
  runbook_document_name        = coalesce(var.ssm_operational_document_name, try(aws_ssm_document.diagnostics[0].name, "AWS-RunShellScript"))
  target_tag_selector          = var.ssm_runbook_target_tag_selector
  patch_operation              = var.ssm_runbook_patch_operation
  runbook_parameters           = var.ssm_runbook_parameters
  require_manual_approval      = var.ssm_runbook_require_manual_approval
  dry_run                      = var.ssm_runbook_dry_run
  sns_topic_arn                = aws_sns_topic.automation_alerts.arn
  approval_sns_topic_arn       = var.ssm_runbook_approval_sns_topic_arn
  lambda_timeout               = 300
  lambda_memory_size           = 256
  log_retention_days           = var.log_retention_days
  tags                         = module.common.tags
}

module "scheduler" {
  count  = var.enable_scheduler ? 1 : 0
  source = "../../modules/automation_scheduler"

  name_prefix                      = module.common.name_prefix
  lambda_source_dir                = "${path.root}/../../lambdas/p0_environment_scheduler"
  enabled                          = true
  start_schedule_expression        = var.scheduler_start_schedule_expression
  stop_schedule_expression         = var.scheduler_stop_schedule_expression
  schedule_timezone                = var.schedule_timezone
  lambda_timeout                   = 900
  lambda_memory_size               = 512
  log_retention_days               = var.log_retention_days
  dry_run                          = var.scheduler_dry_run
  tag_selector                     = var.scheduler_tag_selector
  ec2_pre_stop_ssm_document        = var.scheduler_ec2_pre_stop_ssm_document
  ec2_pre_stop_ssm_timeout_seconds = 600
  tags                             = module.common.tags
}

module "tag_auditor" {
  count  = var.enable_tag_auditor ? 1 : 0
  source = "../../modules/automation_tag_auditor"

  name_prefix         = module.common.name_prefix
  lambda_source_dir   = "${path.root}/../../lambdas/p0_tag_auditor"
  enabled             = true
  schedule_expression = var.tag_auditor_schedule_expression
  schedule_timezone   = var.schedule_timezone
  required_tags       = var.tag_auditor_required_tags
  default_tag_values  = var.tag_auditor_default_tag_values
  dry_run             = var.tag_auditor_dry_run
  auto_remediate      = var.tag_auditor_auto_remediate
  sns_topic_arn       = aws_sns_topic.automation_alerts.arn
  lambda_timeout      = 300
  lambda_memory_size  = 256
  log_retention_days  = var.log_retention_days
  tags                = module.common.tags
}

module "cert_secret_monitor" {
  count  = var.enable_cert_secret_monitor ? 1 : 0
  source = "../../modules/automation_cert_secret_monitor"

  name_prefix                    = module.common.name_prefix
  lambda_source_dir              = "${path.root}/../../lambdas/p0_cert_secret_monitor"
  enabled                        = true
  schedule_expression            = var.cert_secret_monitor_schedule_expression
  schedule_timezone              = var.schedule_timezone
  acm_expiry_threshold_days      = var.acm_expiry_threshold_days
  secret_rotation_threshold_days = var.secret_rotation_threshold_days
  dry_run                        = var.cert_secret_monitor_dry_run
  sns_topic_arn                  = aws_sns_topic.automation_alerts.arn
  lambda_timeout                 = 300
  lambda_memory_size             = 256
  log_retention_days             = var.log_retention_days
  tags                           = module.common.tags
}

module "orphan_cleanup" {
  count  = var.enable_orphan_cleanup ? 1 : 0
  source = "../../modules/automation_orphan_cleanup"

  name_prefix               = module.common.name_prefix
  lambda_source_dir         = "${path.root}/../../lambdas/p0_orphan_cleanup"
  enabled                   = true
  schedule_expression       = var.orphan_cleanup_schedule_expression
  schedule_timezone         = var.schedule_timezone
  snapshot_retention_days   = var.orphan_cleanup_snapshot_retention_days
  log_group_retention_days  = var.orphan_cleanup_log_group_retention_days
  ecr_image_retention_days  = var.orphan_cleanup_ecr_image_retention_days
  dry_run                   = var.orphan_cleanup_dry_run
  allow_destructive_actions = var.orphan_cleanup_allow_destructive_actions
  sns_topic_arn             = aws_sns_topic.automation_alerts.arn
  lambda_timeout            = 900
  lambda_memory_size        = 512
  log_retention_days        = var.log_retention_days
  tags                      = module.common.tags
}

module "incident_evidence" {
  count  = var.enable_incident_evidence ? 1 : 0
  source = "../../modules/automation_incident_evidence"

  name_prefix        = module.common.name_prefix
  lambda_source_dir  = "${path.root}/../../lambdas/p0_incident_evidence"
  enabled            = true
  sns_topic_arn      = aws_sns_topic.automation_alerts.arn
  evidence_prefix    = "incident-evidence"
  target_group_arns  = var.incident_evidence_target_group_arns
  log_group_names    = var.incident_evidence_log_group_names
  ecs_cluster_arns   = var.incident_evidence_ecs_cluster_arns
  eks_cluster_names  = var.incident_evidence_eks_cluster_names
  lambda_timeout     = 900
  lambda_memory_size = 1024
  log_retention_days = var.log_retention_days
  tags               = module.common.tags
}

module "ecs_rollback" {
  count  = var.enable_ecs_rollback ? 1 : 0
  source = "../../modules/automation_ecs_rollback"

  name_prefix                  = module.common.name_prefix
  lambda_source_dir            = "${path.root}/../../lambdas/p0_ecs_rollback"
  stepfunction_definition_path = "${path.root}/../../stepfunctions/p0_ecs_rollback.asl.json"
  enabled                      = true
  enable_event_trigger         = var.enable_ecs_rollback_event_trigger
  sns_topic_arn                = aws_sns_topic.automation_alerts.arn
  lambda_timeout               = 300
  lambda_memory_size           = 512
  log_retention_days           = var.log_retention_days
  tags                         = module.common.tags
}

module "backup_validation" {
  count  = var.enable_backup_validation ? 1 : 0
  source = "../../modules/automation_backup_validation"

  name_prefix                  = module.common.name_prefix
  lambda_source_dir            = "${path.root}/../../lambdas/p0_backup_validation"
  stepfunction_definition_path = "${path.root}/../../stepfunctions/p0_backup_validation.asl.json"
  enabled                      = true
  schedule_expression          = var.backup_validation_schedule_expression
  schedule_timezone            = var.schedule_timezone
  sns_topic_arn                = aws_sns_topic.automation_alerts.arn
  snapshot_max_age_days        = var.backup_validation_snapshot_max_age_days
  dry_run                      = var.backup_validation_dry_run
  allow_restore                = var.backup_validation_allow_restore
  lambda_timeout               = 900
  lambda_memory_size           = 1024
  log_retention_days           = var.log_retention_days
  tags                         = module.common.tags
}

module "sg_exposure_remediation" {
  count  = var.enable_sg_exposure_remediation ? 1 : 0
  source = "../../modules/automation_sg_exposure_remediation"

  name_prefix                  = module.common.name_prefix
  lambda_source_dir            = "${path.root}/../../lambdas/p1_sg_exposure_remediation"
  stepfunction_definition_path = "${path.root}/../../stepfunctions/p1_sg_exposure_remediation.asl.json"
  enabled                      = true
  schedule_expression          = var.sg_remediation_schedule_expression
  schedule_timezone            = var.schedule_timezone
  critical_ports               = var.sg_remediation_critical_ports
  exclude_security_group_ids   = var.sg_remediation_excluded_security_group_ids
  allow_auto_remediation       = var.sg_remediation_allow_auto_remediation
  require_manual_approval      = var.sg_remediation_require_manual_approval
  dry_run                      = var.sg_remediation_dry_run
  sns_topic_arn                = aws_sns_topic.automation_alerts.arn
  lambda_timeout               = 300
  lambda_memory_size           = 256
  log_retention_days           = var.log_retention_days
  tags                         = module.common.tags
}

module "finops_report" {
  count  = var.enable_finops_report ? 1 : 0
  source = "../../modules/automation_finops_report"

  name_prefix         = module.common.name_prefix
  lambda_source_dir   = "${path.root}/../../lambdas/p1_finops_report"
  enabled             = true
  schedule_expression = var.finops_report_schedule_expression
  schedule_timezone   = var.schedule_timezone
  report_bucket_name  = var.finops_report_bucket_name
  report_prefix       = var.finops_report_prefix
  lookback_days       = var.finops_report_lookback_days
  group_by_tag_keys   = var.finops_report_group_by_tag_keys
  sns_topic_arn       = aws_sns_topic.automation_alerts.arn
  dry_run             = var.finops_report_dry_run
  lambda_timeout      = 900
  lambda_memory_size  = 512
  log_retention_days  = var.log_retention_days
  tags                = module.common.tags
}

module "drift_detection" {
  count  = var.enable_drift_detection ? 1 : 0
  source = "../../modules/automation_drift_detection"

  name_prefix         = module.common.name_prefix
  lambda_source_dir   = "${path.root}/../../lambdas/p1_drift_detection"
  enabled             = true
  schedule_expression = var.drift_detection_schedule_expression
  schedule_timezone   = var.schedule_timezone
  storage_bucket_name = var.drift_detection_storage_bucket_name
  baseline_object_key = var.drift_detection_baseline_object_key
  report_prefix       = var.drift_detection_report_prefix
  sns_topic_arn       = aws_sns_topic.automation_alerts.arn
  dry_run             = var.drift_detection_dry_run
  lambda_timeout      = 900
  lambda_memory_size  = 512
  log_retention_days  = var.log_retention_days
  tags                = module.common.tags
}

locals {
  lambda_function_names = concat(
    var.enable_ssm_runbooks_automation ? [module.ssm_runbooks[0].lambda_function_name] : [],
    var.enable_scheduler ? [module.scheduler[0].lambda_function_name] : [],
    var.enable_tag_auditor ? [module.tag_auditor[0].lambda_function_name] : [],
    var.enable_cert_secret_monitor ? [module.cert_secret_monitor[0].lambda_function_name] : [],
    var.enable_orphan_cleanup ? [module.orphan_cleanup[0].lambda_function_name] : [],
    var.enable_incident_evidence ? [module.incident_evidence[0].lambda_function_name] : [],
    var.enable_ecs_rollback ? [module.ecs_rollback[0].lambda_function_name] : [],
    var.enable_backup_validation ? [module.backup_validation[0].lambda_function_name] : [],
    var.enable_sg_exposure_remediation ? [module.sg_exposure_remediation[0].lambda_function_name] : [],
    var.enable_finops_report ? [module.finops_report[0].lambda_function_name] : [],
    var.enable_drift_detection ? [module.drift_detection[0].lambda_function_name] : []
  )

  state_machine_arns = concat(
    var.enable_ecs_rollback ? [module.ecs_rollback[0].state_machine_arn] : [],
    var.enable_backup_validation ? [module.backup_validation[0].state_machine_arn] : [],
    var.enable_sg_exposure_remediation ? [module.sg_exposure_remediation[0].state_machine_arn] : []
  )
}

module "observability" {
  source = "../../modules/observability"

  enabled               = var.enable_observability_alarms
  name_prefix           = module.common.name_prefix
  sns_topic_arn         = aws_sns_topic.automation_alerts.arn
  lambda_function_names = local.lambda_function_names
  state_machine_arns    = local.state_machine_arns
  tags                  = module.common.tags
}
