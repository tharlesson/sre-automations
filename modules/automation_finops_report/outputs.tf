output "lambda_function_name" {
  description = "FinOps report lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "FinOps report lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_arn" {
  description = "FinOps report schedule ARN."
  value       = module.schedule.schedule_arn
}

output "report_bucket_name" {
  description = "S3 bucket used to store FinOps reports."
  value       = local.effective_bucket_name
}