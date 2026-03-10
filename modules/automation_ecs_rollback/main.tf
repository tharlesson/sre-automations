locals {
  rollback_lambda_name = "${var.name_prefix}-ecs-rollback-worker"
  workflow_name        = "${var.name_prefix}-ecs-rollback"

  lambda_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcsRollbackActions"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "ElbHealthRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth"
        ]
        Resource = "*"
      }
    ]
  }

  sfn_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeRollbackLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          module.rollback_lambda.function_arn,
          "${module.rollback_lambda.function_arn}:*"
        ]
      },
      {
        Sid    = "NotifyRollbackStatus"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  }
}

module "rollback_lambda" {
  source = "../lambda_automation"

  name                  = local.rollback_lambda_name
  description           = "Worker lambda for ECS rollback workflow."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.lambda_policy)
  max_retry_attempts    = 1
  max_event_age_seconds = 3600
  tracing_mode          = "Active"
  tags                  = var.tags
}

module "workflow" {
  source = "../sfn_automation"

  name            = local.workflow_name
  definition_path = var.stepfunction_definition_path
  definition_vars = {
    rollback_lambda_arn = module.rollback_lambda.function_arn
    sns_topic_arn       = var.sns_topic_arn
  }
  iam_policy_json    = jsonencode(local.sfn_policy)
  log_retention_days = var.log_retention_days
  tracing_enabled    = true
  tags               = var.tags
}

data "aws_iam_policy_document" "events_assume_role" {
  count = var.enable_event_trigger ? 1 : 0

  statement {
    sid     = "EventBridgeTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_to_sfn" {
  count = var.enable_event_trigger ? 1 : 0

  name               = "${local.workflow_name}-eventbridge-role"
  assume_role_policy = data.aws_iam_policy_document.events_assume_role[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "eventbridge_to_sfn" {
  count = var.enable_event_trigger ? 1 : 0

  name = "${local.workflow_name}-eventbridge-start"
  role = aws_iam_role.eventbridge_to_sfn[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartRollbackExecution"
        Effect   = "Allow"
        Action   = "states:StartExecution"
        Resource = module.workflow.state_machine_arn
      }
    ]
  })
}

resource "aws_cloudwatch_event_rule" "ecs_failure" {
  count = var.enable_event_trigger ? 1 : 0

  name          = "${local.workflow_name}-event"
  description   = "Triggers ECS rollback workflow when deployment failure event is emitted."
  event_pattern = jsonencode(var.ecs_deployment_failure_pattern)

  is_enabled = var.enabled
  tags       = var.tags
}

resource "aws_cloudwatch_event_target" "ecs_failure" {
  count = var.enable_event_trigger ? 1 : 0

  rule      = aws_cloudwatch_event_rule.ecs_failure[0].name
  target_id = "ecs-rollback-workflow"
  arn       = module.workflow.state_machine_arn
  role_arn  = aws_iam_role.eventbridge_to_sfn[0].arn
}