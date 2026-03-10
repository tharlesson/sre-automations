output "lambda_function_name" {
  description = "Rollback worker lambda name."
  value       = module.rollback_lambda.function_name
}

output "lambda_function_arn" {
  description = "Rollback worker lambda ARN."
  value       = module.rollback_lambda.function_arn
}

output "state_machine_name" {
  description = "ECS rollback state machine name."
  value       = module.workflow.state_machine_name
}

output "state_machine_arn" {
  description = "ECS rollback state machine ARN."
  value       = module.workflow.state_machine_arn
}

output "event_rule_arn" {
  description = "Optional event rule ARN when event trigger is enabled."
  value       = try(aws_cloudwatch_event_rule.ecs_failure[0].arn, null)
}