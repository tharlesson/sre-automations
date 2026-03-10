locals {
  group_name     = coalesce(var.group_name, try(aws_scheduler_schedule_group.this[0].name, null))
  create_role    = var.create_invoke_role
  effective_role = local.create_role ? aws_iam_role.invoke[0].arn : var.invoke_role_arn
  target_action  = var.target_type == "lambda" ? "lambda:InvokeFunction" : "states:StartExecution"
  input_payload  = length(var.target_input) > 0 ? jsonencode(var.target_input) : null
}

resource "aws_scheduler_schedule_group" "this" {
  count = var.group_name == null ? 1 : 0

  name = "${var.name}-group"
  tags = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  count = local.create_role ? 1 : 0

  statement {
    sid     = "SchedulerTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "invoke" {
  count = local.create_role ? 1 : 0

  name               = "${var.name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "invoke" {
  count = local.create_role ? 1 : 0

  statement {
    sid       = "InvokeTarget"
    actions   = [local.target_action]
    resources = [var.target_arn]
  }
}

resource "aws_iam_role_policy" "invoke" {
  count = local.create_role ? 1 : 0

  name   = "${var.name}-scheduler-invoke"
  role   = aws_iam_role.invoke[0].id
  policy = data.aws_iam_policy_document.invoke[0].json
}

resource "aws_scheduler_schedule" "this" {
  name                         = var.name
  description                  = var.description
  group_name                   = local.group_name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = var.target_arn
    role_arn = local.effective_role
    input    = local.input_payload

    retry_policy {
      maximum_event_age_in_seconds = var.maximum_event_age_seconds
      maximum_retry_attempts       = var.maximum_retry_attempts
    }

    dynamic "dead_letter_config" {
      for_each = var.dead_letter_arn != null ? [1] : []
      content {
        arn = var.dead_letter_arn
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.create_role || var.invoke_role_arn != null
      error_message = "invoke_role_arn is required when create_invoke_role is false."
    }
  }
}

resource "aws_lambda_permission" "allow_scheduler" {
  count = var.target_type == "lambda" ? 1 : 0

  statement_id  = "AllowSchedulerInvoke${replace(var.name, "-", "")}"
  action        = "lambda:InvokeFunction"
  function_name = var.target_arn
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.this.arn
}