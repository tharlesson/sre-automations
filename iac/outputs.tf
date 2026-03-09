output "lambda_function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.environment_scheduler.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN."
  value       = aws_lambda_function.environment_scheduler.arn
}

output "state_bucket_name" {
  description = "S3 bucket name used for state persistence."
  value       = module.state_bucket.bucket_name
}

output "state_object_key" {
  description = "S3 object key used for state persistence."
  value       = var.state_object_key
}

output "scheduler_start_arn" {
  description = "AWS Scheduler start schedule ARN."
  value       = aws_scheduler_schedule.start.arn
}

output "scheduler_stop_arn" {
  description = "AWS Scheduler stop schedule ARN."
  value       = aws_scheduler_schedule.stop.arn
}
