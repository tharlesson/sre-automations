output "schedule_name" {
  description = "Schedule name."
  value       = aws_scheduler_schedule.this.name
}

output "schedule_arn" {
  description = "Schedule ARN."
  value       = aws_scheduler_schedule.this.arn
}

output "group_name" {
  description = "Scheduler group name."
  value       = local.group_name
}

output "invoke_role_arn" {
  description = "Scheduler invoke role ARN."
  value       = local.effective_role
}