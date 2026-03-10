output "lambda_function_name" {
  description = "Backup validation worker lambda name."
  value       = module.worker_lambda.function_name
}

output "state_machine_name" {
  description = "Backup validation state machine name."
  value       = module.workflow.state_machine_name
}

output "state_machine_arn" {
  description = "Backup validation state machine ARN."
  value       = module.workflow.state_machine_arn
}

output "schedule_arn" {
  description = "Backup validation schedule ARN."
  value       = module.schedule.schedule_arn
}

output "evidence_bucket_name" {
  description = "Backup validation evidence bucket name."
  value       = aws_s3_bucket.evidence.bucket
}