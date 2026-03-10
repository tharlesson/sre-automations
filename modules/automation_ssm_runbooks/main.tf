locals {
  lambda_name        = "${var.name_prefix}-ssm-runbooks"
  scheduler_group    = "${var.name_prefix}-ssm-runbooks"
  approval_topic_arn = coalesce(var.approval_sns_topic_arn, var.sns_topic_arn)

  lambda_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2Describe"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "SsmCommands"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      },
      {
        Sid    = "Notifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = [
          var.sns_topic_arn,
          local.approval_topic_arn,
        ]
      }
    ]
  }
}

resource "aws_scheduler_schedule_group" "this" {
  name = local.scheduler_group
  tags = var.tags
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Execute SSM patching and operational runbooks in controlled windows."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.lambda_policy)
  max_retry_attempts    = 2
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  tags                  = var.tags

  environment_variables = {
    PATCHING_DOCUMENT_NAME   = var.patching_document_name
    RUNBOOK_DOCUMENT_NAME    = var.runbook_document_name
    TARGET_TAG_SELECTOR_JSON = jsonencode(var.target_tag_selector)
    PATCH_OPERATION          = var.patch_operation
    RUNBOOK_PARAMETERS_JSON  = jsonencode(var.runbook_parameters)
    REQUIRE_MANUAL_APPROVAL  = tostring(var.require_manual_approval)
    DRY_RUN                  = tostring(var.dry_run)
    SNS_TOPIC_ARN            = var.sns_topic_arn
    APPROVAL_SNS_TOPIC_ARN   = local.approval_topic_arn
  }
}

module "patching_schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-patching"
  description         = "Patching execution window for SSM operations."
  group_name          = aws_scheduler_schedule_group.this.name
  schedule_expression = var.patching_schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled && var.enable_patching_schedule
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action    = "patching"
    approved  = false
    initiated = "scheduler"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}

module "runbook_schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-runbook"
  description         = "Operational runbook execution window for SSM operations."
  group_name          = aws_scheduler_schedule_group.this.name
  schedule_expression = var.runbook_schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled && var.enable_runbook_schedule
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action    = "runbook"
    approved  = false
    initiated = "scheduler"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}