output "lambda_function_name" {
  description = "Orphan cleanup lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Orphan cleanup lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_arn" {
  description = "Orphan cleanup schedule ARN."
  value       = module.schedule.schedule_arn
}