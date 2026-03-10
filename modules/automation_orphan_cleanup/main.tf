locals {
  lambda_name = "${var.name_prefix}-orphan-cleanup"

  policy_doc = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2ReadDelete"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeVolumes",
          "ec2:DeleteVolume",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeAddresses",
          "ec2:ReleaseAddress"
        ]
        Resource = "*"
      },
      {
        Sid    = "EcrReadDelete"
        Effect = "Allow"
        Action = [
          "ecr:DescribeRepositories",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:BatchDeleteImage"
        ]
        Resource = "*"
      },
      {
        Sid    = "LogsReadDelete"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DeleteLogGroup"
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
  description           = "Controlled cleanup for orphan and stale AWS resources."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.policy_doc)
  max_retry_attempts    = 1
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  tags                  = var.tags

  environment_variables = {
    SNAPSHOT_RETENTION_DAYS   = tostring(var.snapshot_retention_days)
    LOG_GROUP_RETENTION_DAYS  = tostring(var.log_group_retention_days)
    ECR_IMAGE_RETENTION_DAYS  = tostring(var.ecr_image_retention_days)
    DRY_RUN                   = tostring(var.dry_run)
    ALLOW_DESTRUCTIVE_ACTIONS = tostring(var.allow_destructive_actions)
    SNS_TOPIC_ARN             = var.sns_topic_arn
  }
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-daily"
  description         = "Runs controlled orphan cleanup/report."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  dead_letter_arn     = module.lambda.dlq_arn
  tags                = var.tags
}
