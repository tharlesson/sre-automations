output "state_machine_name" {
  description = "State machine name."
  value       = aws_sfn_state_machine.this.name
}

output "state_machine_arn" {
  description = "State machine ARN."
  value       = aws_sfn_state_machine.this.arn
}

output "role_arn" {
  description = "Step Functions IAM role ARN."
  value       = aws_iam_role.this.arn
}

output "log_group_name" {
  description = "Step Functions log group."
  value       = aws_cloudwatch_log_group.this.name
}