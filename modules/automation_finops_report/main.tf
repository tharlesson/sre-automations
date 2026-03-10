locals {
  lambda_name           = "${var.name_prefix}-finops-report"
  create_bucket         = var.report_bucket_name == null
  effective_bucket_name = coalesce(var.report_bucket_name, try(aws_s3_bucket.reports[0].bucket, null))
  effective_bucket_arn  = var.report_bucket_name == null ? try(aws_s3_bucket.reports[0].arn, null) : "arn:aws:s3:::${var.report_bucket_name}"

  lambda_policy_statements = concat(
    [
      {
        Sid    = "CostExplorerRead"
        Effect = "Allow"
        Action = [
          "ce:GetCostAndUsage",
          "ce:GetDimensionValues",
          "ce:GetSavingsPlansUtilization",
          "ce:GetReservationUtilization"
        ]
        Resource = "*"
      },
      {
        Sid    = "ComputeOptimizerRead"
        Effect = "Allow"
        Action = [
          "compute-optimizer:GetEnrollmentStatus",
          "compute-optimizer:GetEC2InstanceRecommendations"
        ]
        Resource = "*"
      },
      {
        Sid    = "OrganizationsRead"
        Effect = "Allow"
        Action = [
          "organizations:ListAccounts"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReportsWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${local.effective_bucket_arn}/${var.report_prefix}/*"
      }
    ],
    var.sns_topic_arn == null ? [] : [
      {
        Sid    = "Notifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  )
}

resource "aws_s3_bucket" "reports" {
  count = local.create_bucket ? 1 : 0

  bucket = "${var.name_prefix}-finops-reports"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "reports" {
  count = local.create_bucket ? 1 : 0

  bucket = aws_s3_bucket.reports[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  count = local.create_bucket ? 1 : 0

  bucket = aws_s3_bucket.reports[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "reports" {
  count = local.create_bucket ? 1 : 0

  bucket = aws_s3_bucket.reports[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Generate automated FinOps reports (JSON/CSV) and store in S3."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode({ Version = "2012-10-17", Statement = local.lambda_policy_statements })
  max_retry_attempts    = 2
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  tags                  = var.tags

  environment_variables = {
    REPORT_BUCKET                  = local.effective_bucket_name
    REPORT_PREFIX                  = var.report_prefix
    LOOKBACK_DAYS                  = tostring(var.lookback_days)
    GROUP_BY_TAG_KEYS_JSON         = jsonencode(var.group_by_tag_keys)
    INCLUDE_SAVINGS_PLANS_ANALYSIS = tostring(var.include_savings_plans_analysis)
    INCLUDE_RESERVATION_ANALYSIS   = tostring(var.include_reservation_analysis)
    INCLUDE_RIGHTSIZING_ANALYSIS   = tostring(var.include_rightsizing_analysis)
    RIGHTSIZING_MAX_RESULTS        = tostring(var.rightsizing_max_results)
    SNS_TOPIC_ARN                  = coalesce(var.sns_topic_arn, "")
    DRY_RUN                        = tostring(var.dry_run)
  }
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-weekly"
  description         = "Trigger FinOps report generation."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action = "generate_report"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}
