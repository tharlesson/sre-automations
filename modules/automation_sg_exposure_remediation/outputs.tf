output "lambda_function_name" {
  description = "Security group remediation worker lambda name."
  value       = module.worker_lambda.function_name
}

output "lambda_function_arn" {
  description = "Security group remediation worker lambda ARN."
  value       = module.worker_lambda.function_arn
}

output "state_machine_name" {
  description = "SG remediation workflow name."
  value       = module.workflow.state_machine_name
}

output "state_machine_arn" {
  description = "SG remediation workflow ARN."
  value       = module.workflow.state_machine_arn
}

output "schedule_arn" {
  description = "SG remediation schedule ARN."
  value       = module.schedule.schedule_arn
}