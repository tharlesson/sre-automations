output "lambda_function_name" {
  description = "Approval bridge lambda name."
  value       = module.lambda.function_name
}

output "lambda_function_arn" {
  description = "Approval bridge lambda ARN."
  value       = module.lambda.function_arn
}

output "subscription_arn" {
  description = "SNS subscription ARN for approval bridge lambda."
  value       = try(aws_sns_topic_subscription.lambda[0].arn, null)
}