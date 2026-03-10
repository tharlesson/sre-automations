output "lambda_function_name" {
  description = "SSM runbooks lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "SSM runbooks lambda ARN."
  value       = module.lambda.function_arn
}

output "patching_schedule_arn" {
  description = "Patching scheduler ARN."
  value       = module.patching_schedule.schedule_arn
}

output "runbook_schedule_arn" {
  description = "Runbook scheduler ARN."
  value       = module.runbook_schedule.schedule_arn
}