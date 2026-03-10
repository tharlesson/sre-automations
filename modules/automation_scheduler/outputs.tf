output "lambda_function_name" {
  description = "Scheduler lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Scheduler lambda ARN."
  value       = module.lambda.function_arn
}

output "schedule_start_arn" {
  description = "EventBridge Scheduler ARN for start action."
  value       = module.schedule_start.schedule_arn
}

output "schedule_stop_arn" {
  description = "EventBridge Scheduler ARN for stop action."
  value       = module.schedule_stop.schedule_arn
}

output "state_bucket_name" {
  description = "S3 bucket used to persist scheduler state."
  value       = aws_s3_bucket.state.bucket
}