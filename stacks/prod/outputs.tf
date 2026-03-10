output "name_prefix" {
  description = "Naming prefix in format <project>-<environment>-<region>."
  value       = module.common.name_prefix
}

output "automation_alerts_topic_arn" {
  description = "SNS topic ARN for platform alerts."
  value       = aws_sns_topic.automation_alerts.arn
}

output "approval_requests_topic_arn" {
  description = "SNS topic ARN for approval requests."
  value       = aws_sns_topic.approval_requests.arn
}

output "scheduler_lambda_arn" {
  description = "Environment scheduler lambda ARN."
  value       = try(module.scheduler[0].lambda_function_arn, null)
}

output "ssm_runbooks_lambda_arn" {
  description = "SSM runbooks automation lambda ARN."
  value       = try(module.ssm_runbooks[0].lambda_function_arn, null)
}

output "approval_bridge_lambda_arn" {
  description = "Approval bridge lambda ARN."
  value       = try(module.approval_bridge[0].lambda_function_arn, null)
}

output "tag_auditor_lambda_arn" {
  description = "Tag auditor lambda ARN."
  value       = try(module.tag_auditor[0].lambda_function_arn, null)
}

output "cert_secret_monitor_lambda_arn" {
  description = "Certificate/secrets monitor lambda ARN."
  value       = try(module.cert_secret_monitor[0].lambda_function_arn, null)
}

output "orphan_cleanup_lambda_arn" {
  description = "Orphan cleanup lambda ARN."
  value       = try(module.orphan_cleanup[0].lambda_function_arn, null)
}

output "incident_evidence_lambda_arn" {
  description = "Incident evidence lambda ARN."
  value       = try(module.incident_evidence[0].lambda_function_arn, null)
}

output "ecs_rollback_state_machine_arn" {
  description = "ECS rollback workflow ARN."
  value       = try(module.ecs_rollback[0].state_machine_arn, null)
}

output "backup_validation_state_machine_arn" {
  description = "Backup validation workflow ARN."
  value       = try(module.backup_validation[0].state_machine_arn, null)
}

output "sg_exposure_remediation_state_machine_arn" {
  description = "Security group exposure remediation workflow ARN."
  value       = try(module.sg_exposure_remediation[0].state_machine_arn, null)
}

output "finops_report_lambda_arn" {
  description = "FinOps report lambda ARN."
  value       = try(module.finops_report[0].lambda_function_arn, null)
}

output "finops_report_bucket_name" {
  description = "S3 bucket used for FinOps reports."
  value       = try(module.finops_report[0].report_bucket_name, null)
}

output "drift_detection_lambda_arn" {
  description = "Drift detection lambda ARN."
  value       = try(module.drift_detection[0].lambda_function_arn, null)
}

output "drift_detection_bucket_name" {
  description = "S3 bucket used by drift detection."
  value       = try(module.drift_detection[0].storage_bucket_name, null)
}

output "drift_detection_baseline_s3_uri" {
  description = "S3 URI of configured drift baseline object."
  value       = try(module.drift_detection[0].baseline_s3_uri, null)
}

output "observability_lambda_alarm_names" {
  description = "Lambda alarm names created for observability baseline."
  value       = module.observability.lambda_alarm_names
}

output "observability_sfn_alarm_names" {
  description = "Step Functions alarm names created for observability baseline."
  value       = module.observability.sfn_alarm_names
}

output "ssm_documents" {
  description = "Reusable SSM document names."
  value = {
    patching                = try(aws_ssm_document.patching[0].name, null)
    diagnostics             = try(aws_ssm_document.diagnostics[0].name, null)
    cleanup_disk            = try(aws_ssm_document.cleanup_disk[0].name, null)
    service_restart         = try(aws_ssm_document.service_restart[0].name, null)
    sg_remediation_approval = try(aws_ssm_document.sg_remediation_approval[0].name, null)
  }
}
