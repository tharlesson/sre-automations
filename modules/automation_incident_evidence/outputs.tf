output "lambda_function_name" {
  description = "Incident evidence lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Incident evidence lambda ARN."
  value       = module.lambda.function_arn
}

output "event_rule_arn" {
  description = "EventBridge rule ARN for alarms."
  value       = aws_cloudwatch_event_rule.alarm.arn
}

output "evidence_bucket_name" {
  description = "S3 evidence bucket name."
  value       = aws_s3_bucket.evidence.bucket
}