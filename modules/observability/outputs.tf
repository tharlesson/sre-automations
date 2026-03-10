output "lambda_alarm_names" {
  description = "Created Lambda alarm names."
  value       = [for alarm in aws_cloudwatch_metric_alarm.lambda_errors : alarm.alarm_name]
}

output "sfn_alarm_names" {
  description = "Created Step Functions alarm names."
  value       = [for alarm in aws_cloudwatch_metric_alarm.sfn_failures : alarm.alarm_name]
}