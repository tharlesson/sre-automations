locals {
  lambda_name = "${var.name_prefix}-cert-secret-monitor"

  policy_doc = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCertificates"
        Effect = "Allow"
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets",
          "secretsmanager:DescribeSecret"
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
  description           = "Monitors ACM certificate and secrets expiration/rotation windows."
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
    ACM_EXPIRY_THRESHOLD_DAYS      = tostring(var.acm_expiry_threshold_days)
    SECRET_ROTATION_THRESHOLD_DAYS = tostring(var.secret_rotation_threshold_days)
    DRY_RUN                        = tostring(var.dry_run)
    SNS_TOPIC_ARN                  = var.sns_topic_arn
  }
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-daily"
  description         = "Runs certificate and secret monitor."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  dead_letter_arn     = module.lambda.dlq_arn
  tags                = var.tags
}