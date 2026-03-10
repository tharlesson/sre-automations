data "aws_caller_identity" "current" {}

locals {
  lambda_name      = "${var.name_prefix}-incident-evidence"
  rule_name        = "${var.name_prefix}-incident-evidence-rule"
  effective_bucket = coalesce(var.evidence_bucket_name, "${var.name_prefix}-incident-evidence-${data.aws_caller_identity.current.account_id}")

  policy_doc = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EcsEksRead"
        Effect = "Allow"
        Action = [
          "ecs:ListClusters",
          "ecs:ListServices",
          "ecs:DescribeServices",
          "eks:ListClusters",
          "eks:DescribeCluster",
          "eks:ListUpdates",
          "eks:DescribeUpdate"
        ]
        Resource = "*"
      },
      {
        Sid    = "ElbRead"
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "CodeDeployRead"
        Effect = "Allow"
        Action = [
          "codedeploy:ListApplications",
          "codedeploy:ListDeploymentGroups",
          "codedeploy:ListDeployments",
          "codedeploy:GetDeployment"
        ]
        Resource = "*"
      },
      {
        Sid    = "WriteEvidence"
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.evidence.arn}/${var.evidence_prefix}/*"
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

resource "aws_s3_bucket" "evidence" {
  bucket = local.effective_bucket
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

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Collects incident evidence on alarm and stores structured JSON in S3."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.policy_doc)
  max_retry_attempts    = 2
  max_event_age_seconds = 3600
  tracing_mode          = "Active"
  tags                  = var.tags

  environment_variables = {
    EVIDENCE_BUCKET   = aws_s3_bucket.evidence.bucket
    EVIDENCE_PREFIX   = var.evidence_prefix
    SNS_TOPIC_ARN     = var.sns_topic_arn
    TARGET_GROUP_ARNS = jsonencode(var.target_group_arns)
    LOG_GROUP_NAMES   = jsonencode(var.log_group_names)
    ECS_CLUSTER_ARNS  = jsonencode(var.ecs_cluster_arns)
    EKS_CLUSTER_NAMES = jsonencode(var.eks_cluster_names)
  }
}

resource "aws_cloudwatch_event_rule" "alarm" {
  name          = local.rule_name
  description   = "Triggers incident evidence collector when alarms reach ALARM state."
  event_pattern = jsonencode(var.alarm_event_pattern)

  is_enabled = var.enabled
  tags       = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.alarm.name
  target_id = "incident-evidence-lambda"
  arn       = module.lambda.function_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvokeIncidentEvidence"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.alarm.arn
}