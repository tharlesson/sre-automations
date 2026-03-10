locals {
  lambda_name          = "${var.name_prefix}-drift-detection"
  create_storage       = var.storage_bucket_name == null
  effective_bucket     = coalesce(var.storage_bucket_name, try(aws_s3_bucket.storage[0].bucket, null))
  effective_bucket_arn = var.storage_bucket_name == null ? try(aws_s3_bucket.storage[0].arn, null) : "arn:aws:s3:::${var.storage_bucket_name}"

  lambda_policy_statements = concat(
    [
      {
        Sid    = "S3BaselineAndReports"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${local.effective_bucket_arn}/${var.baseline_object_key}",
          "${local.effective_bucket_arn}/${var.report_prefix}/*",
        ]
      },
      {
        Sid    = "ReadSecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadEcsServices"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadListeners"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeListeners"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadParameters"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "*"
      },
      {
        Sid    = "ReadResourceTags"
        Effect = "Allow"
        Action = [
          "tag:GetResources"
        ]
        Resource = "*"
      }
    ],
    var.sns_topic_arn == null ? [] : [
      {
        Sid    = "NotifyDrift"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  )
}

resource "aws_s3_bucket" "storage" {
  count = local.create_storage ? 1 : 0

  bucket = "${var.name_prefix}-drift-detection"
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "storage" {
  count = local.create_storage ? 1 : 0

  bucket = aws_s3_bucket.storage[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  count = local.create_storage ? 1 : 0

  bucket = aws_s3_bucket.storage[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "storage" {
  count = local.create_storage ? 1 : 0

  bucket = aws_s3_bucket.storage[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Detect operational drifts in critical resources and alert with report evidence."
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
    STORAGE_BUCKET      = local.effective_bucket
    BASELINE_OBJECT_KEY = var.baseline_object_key
    REPORT_PREFIX       = var.report_prefix
    SNS_TOPIC_ARN       = coalesce(var.sns_topic_arn, "")
    DRY_RUN             = tostring(var.dry_run)
  }
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-daily"
  description         = "Trigger drift detection report generation."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action = "detect_drift"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}
