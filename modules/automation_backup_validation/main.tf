data "aws_caller_identity" "current" {}

locals {
  lambda_name     = "${var.name_prefix}-backup-validation-worker"
  workflow_name   = "${var.name_prefix}-backup-validation"
  evidence_bucket = coalesce(var.evidence_bucket_name, "${var.name_prefix}-backup-evidence-${data.aws_caller_identity.current.account_id}")

  lambda_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2SnapshotValidation"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:CreateVolume",
          "ec2:DeleteVolume",
          "ec2:DescribeVolumes"
        ]
        Resource = "*"
      },
      {
        Sid    = "RdsSnapshotValidation"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBSnapshots",
          "rds:DescribeDBClusterSnapshots"
        ]
        Resource = "*"
      },
      {
        Sid    = "EvidenceStorage"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.evidence.arn}/${var.evidence_prefix}/*"
      },
      {
        Sid    = "PublishNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
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
        Sid    = "PublishWorkflowNotifications"
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn
      }
    ]
  }
}

resource "aws_s3_bucket" "evidence" {
  bucket = local.evidence_bucket
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "evidence" {
  bucket = aws_s3_bucket.evidence.id

  versioning_configuration {
    status = "Enabled"
  }
}

module "worker_lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Worker lambda for backup validation and temporary restore checks."
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

  environment_variables = {
    EVIDENCE_BUCKET       = aws_s3_bucket.evidence.bucket
    EVIDENCE_PREFIX       = var.evidence_prefix
    SNAPSHOT_MAX_AGE_DAYS = tostring(var.snapshot_max_age_days)
    DRY_RUN               = tostring(var.dry_run)
    ALLOW_RESTORE         = tostring(var.allow_restore)
    SNS_TOPIC_ARN         = var.sns_topic_arn
  }
}

module "workflow" {
  source = "../sfn_automation"

  name            = local.workflow_name
  definition_path = var.stepfunction_definition_path
  definition_vars = {
    worker_lambda_arn = module.worker_lambda.function_arn
    sns_topic_arn     = var.sns_topic_arn
  }
  iam_policy_json    = jsonencode(local.sfn_policy)
  log_retention_days = var.log_retention_days
  tracing_enabled    = true
  tags               = var.tags
}

module "schedule" {
  source = "../eventbridge_schedule"

  name                = "${local.workflow_name}-weekly"
  description         = "Triggers backup validation workflow."
  schedule_expression = var.schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.workflow.state_machine_arn
  target_type         = "sfn"
  target_input = {
    trigger = "scheduled"
  }
  tags = var.tags
}