locals {
  lambda_name = "${var.name_prefix}-tag-auditor"

  policy_doc = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadTaggedResources"
        Effect = "Allow"
        Action = [
          "tag:GetResources"
        ]
        Resource = "*"
      },
      {
        Sid    = "OptionalTagRemediation"
        Effect = "Allow"
        Action = [
          "tag:TagResources"
        ]
        Resource = "*"
      },
      {
        Sid    = "PublishAlerts"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  }
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Audits mandatory tags and optionally remediates non-compliant resources."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.policy_doc)
  max_retry_attempts    = 2
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  tags                  = var.tags

  environment_variables = {
    REQUIRED_TAGS_JSON      = jsonencode(var.required_tags)
    DEFAULT_TAG_VALUES_JSON = jsonencode(var.default_tag_values)
    DRY_RUN                 = tostring(var.dry_run)
    AUTO_REMEDIATE          = tostring(var.auto_remediate)
    SNS_TOPIC_ARN           = var.sns_topic_arn
  }
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-daily"
  description         = "Runs mandatory tags auditor."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  dead_letter_arn     = module.lambda.dlq_arn
  tags                = var.tags
}