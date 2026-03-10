locals {
  lambda_name        = "${var.name_prefix}-sg-exposure-remediation"
  workflow_name      = "${var.name_prefix}-sg-exposure-remediation"
  approval_topic_arn = coalesce(var.approval_sns_topic_arn, var.sns_topic_arn)

  lambda_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "RevokeIngress"
        Effect = "Allow"
        Action = [
          "ec2:RevokeSecurityGroupIngress"
        ]
        Resource = "*"
      }
    ]
  }

  sfn_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeWorkerLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          module.worker_lambda.function_arn,
          "${module.worker_lambda.function_arn}:*"
        ]
      },
      {
        Sid    = "NotifySecurityFindings"
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

module "worker_lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Detect and optionally remediate exposed security groups."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.lambda_policy)
  max_retry_attempts    = 1
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  tags                  = var.tags

  environment_variables = {
    CRITICAL_PORTS_JSON           = jsonencode(var.critical_ports)
    EXCLUDED_SECURITY_GROUPS_JSON = jsonencode(var.exclude_security_group_ids)
    DRY_RUN                       = tostring(var.dry_run)
  }
}

module "workflow" {
  source = "../sfn_automation"

  name            = local.workflow_name
  definition_path = var.stepfunction_definition_path
  definition_vars = {
    sg_lambda_arn          = module.worker_lambda.function_arn
    sns_topic_arn          = var.sns_topic_arn
    approval_sns_topic_arn = local.approval_topic_arn
  }
  iam_policy_json    = jsonencode(local.sfn_policy)
  log_retention_days = var.log_retention_days
  tracing_enabled    = true
  tags               = var.tags
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.workflow_name}-daily"
  description         = "Trigger SG exposure detection/remediation workflow."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.workflow.state_machine_arn
  target_type         = "sfn"
  target_input = {
    approved                = false
    allow_auto_remediation  = var.allow_auto_remediation
    require_manual_approval = var.require_manual_approval
    dry_run                 = var.dry_run
  }
  tags = var.tags
}
