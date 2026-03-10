output "lambda_function_name" {
  description = "Cert/secret monitor lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Cert/secret monitor lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_arn" {
  description = "Cert/secret monitor schedule ARN."
  value       = module.schedule.schedule_arn
}