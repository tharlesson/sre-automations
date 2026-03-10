output "lambda_function_name" {
  description = "Tag auditor lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Tag auditor lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_arn" {
  description = "Tag auditor schedule ARN."
  value       = module.schedule.schedule_arn
}