terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  lambda_name      = "${var.name_prefix}-env-scheduler"
  scheduler_group  = "${var.name_prefix}-env-scheduler"
  effective_bucket = coalesce(var.state_bucket_name, "${var.name_prefix}-scheduler-state-${data.aws_caller_identity.current.account_id}")
  policy_statements = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ec2Management"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ]
        Resource = "*"
      },
      {
        Sid    = "RdsManagement"
        Effect = "Allow"
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeDBClusters",
          "rds:ListTagsForResource",
          "rds:StartDBInstance",
          "rds:StopDBInstance",
          "rds:StartDBCluster",
          "rds:StopDBCluster"
        ]
        Resource = "*"
      },
      {
        Sid    = "EcsManagement"
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "ecs:UpdateService"
        ]
        Resource = "*"
      },
      {
        Sid    = "AsgManagement"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeTags",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "SsmPreStop"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations"
        ]
        Resource = "*"
      },
      {
        Sid    = "StateObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.state.arn}/${var.state_object_key}"
      }
    ]
  }
}

resource "aws_scheduler_schedule_group" "this" {
  name = local.scheduler_group
  tags = var.tags
}

resource "aws_s3_bucket" "state" {
  bucket        = local.effective_bucket
  force_destroy = var.state_bucket_force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Automation to start/stop non-prod resources using tags and schedules."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.policy_statements)
  max_retry_attempts    = 2
  max_event_age_seconds = 3600
  tracing_mode          = "Active"
  tags                  = var.tags

  environment_variables = {
    DRY_RUN                          = tostring(var.dry_run)
    TAG_SELECTOR_JSON                = jsonencode(var.tag_selector)
    STATE_BUCKET                     = aws_s3_bucket.state.bucket
    STATE_OBJECT_KEY                 = var.state_object_key
    EC2_PRE_STOP_SSM_DOCUMENT        = coalesce(var.ec2_pre_stop_ssm_document, "")
    EC2_PRE_STOP_SSM_TIMEOUT_SECONDS = tostring(var.ec2_pre_stop_ssm_timeout_seconds)
  }
}

module "schedule_start" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-start"
  description         = "Start tagged resources in non-production environments."
  group_name          = aws_scheduler_schedule_group.this.name
  schedule_expression = var.start_schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action = "start"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}

module "schedule_stop" {
  source = "../eventbridge_schedule"

  name                = "${local.lambda_name}-stop"
  description         = "Stop tagged resources in non-production environments."
  group_name          = aws_scheduler_schedule_group.this.name
  schedule_expression = var.stop_schedule_expression
  schedule_timezone   = var.schedule_timezone
  enabled             = var.enabled
  target_arn          = module.lambda.function_arn
  target_type         = "lambda"
  target_input = {
    action = "stop"
  }
  dead_letter_arn = module.lambda.dlq_arn
  tags            = var.tags
}
