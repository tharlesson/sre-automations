locals {
  lambda_targets = var.enabled ? toset(var.lambda_function_names) : []
  sfn_targets    = var.enabled ? toset(var.state_machine_arns) : []
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = local.lambda_targets

  alarm_name          = "${var.name_prefix}-${each.value}-lambda-errors"
  alarm_description   = "Lambda errors detected for ${each.value}."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "sfn_failures" {
  for_each = local.sfn_targets

  alarm_name          = "${var.name_prefix}-${replace(each.value, ":", "-")}-sfn-failures"
  alarm_description   = "Step Functions execution failure detected for ${each.value}."
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  statistic           = "Sum"
  period              = var.period_seconds
  evaluation_periods  = var.evaluation_periods
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StateMachineArn = each.value
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
  tags          = var.tags
}