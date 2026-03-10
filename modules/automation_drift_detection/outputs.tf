output "lambda_function_name" {
  description = "Drift detection lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Drift detection lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_arn" {
  description = "Drift detection schedule ARN."
  value       = module.schedule.schedule_arn
}

output "storage_bucket_name" {
  description = "S3 bucket used for baseline and drift reports."
  value       = local.effective_bucket
}