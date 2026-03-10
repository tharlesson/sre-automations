data "aws_caller_identity" "current" {}

locals {
  stack       = "environment-scheduler"
  name_prefix = "${var.client}-${var.environment}-${var.application}"

  effective_state_bucket_name = coalesce(
    var.state_bucket_name,
    "${var.client}-${var.environment}-${var.application}-state-${data.aws_caller_identity.current.account_id}-${var.region}"
  )

  common_tags = merge(var.tags, {
    Client      = var.client
    Environment = var.environment
    Stack       = local.stack
    Application = var.application
  })
}

module "state_bucket" {
  source = "../../terraform-modules/modules/s3"

  bucket_name                                  = local.effective_state_bucket_name
  access_log_bucket_name                       = coalesce(var.state_access_log_bucket_name, local.effective_state_bucket_name)
  access_log_prefix                            = var.state_access_log_prefix
  force_destroy                                = var.state_bucket_force_destroy
  versioning_status                            = "Enabled"
  sse_algorithm                                = var.state_bucket_sse_algorithm
  kms_key_arn                                  = var.state_bucket_kms_key_arn
  lifecycle_current_version_expiration_days    = var.state_bucket_lifecycle_current_days
  lifecycle_noncurrent_version_expiration_days = var.state_bucket_lifecycle_noncurrent_days
  tags                                         = local.common_tags
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/src"
  output_path = "${path.module}/environment_scheduler_lambda.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "LambdaTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_execution" {
  name               = "${local.name_prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }

  statement {
    sid = "Ec2StartStop"
    actions = [
      "ec2:DescribeInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]
    resources = ["*"]
  }

  statement {
    sid = "RdsStartStop"
    actions = [
      "rds:DescribeDBInstances",
      "rds:DescribeDBClusters",
      "rds:ListTagsForResource",
      "rds:StartDBInstance",
      "rds:StopDBInstance",
      "rds:StartDBCluster",
      "rds:StopDBCluster",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EcsManageServices"
    actions = [
      "ecs:ListClusters",
      "ecs:ListServices",
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  statement {
    sid = "EksAndStsRead"
    actions = [
      "eks:ListClusters",
      "eks:DescribeCluster",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid = "StateBucketReadWrite"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [
      "${module.state_bucket.bucket_arn}/${var.state_object_key}",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name   = "${local.name_prefix}-lambda-policy"
  role   = aws_iam_role.lambda_execution.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.name_prefix}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "environment_scheduler" {
  function_name    = local.name_prefix
  role             = aws_iam_role.lambda_execution.arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  memory_size      = var.lambda_memory_size
  timeout          = var.lambda_timeout
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DRY_RUN                 = tostring(var.dry_run)
      EKS_EXCLUDED_NAMESPACES = join(",", var.eks_excluded_namespaces)
      LOG_LEVEL               = var.log_level
      RESTORE_DELAY_SECONDS   = tostring(var.restore_delay_seconds)
      STATE_BUCKET            = module.state_bucket.bucket_name
      STATE_OBJECT_KEY        = var.state_object_key
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_permissions,
  ]

  tags = local.common_tags
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "SchedulerTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler_invoke_lambda" {
  name               = "${local.name_prefix}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "scheduler_invoke_lambda" {
  statement {
    sid = "AllowInvokeLambda"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [
      aws_lambda_function.environment_scheduler.arn,
      "${aws_lambda_function.environment_scheduler.arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name   = "${local.name_prefix}-scheduler-invoke"
  role   = aws_iam_role.scheduler_invoke_lambda.id
  policy = data.aws_iam_policy_document.scheduler_invoke_lambda.json
}

resource "aws_scheduler_schedule_group" "this" {
  name = "${local.name_prefix}-group"
}

resource "aws_scheduler_schedule" "start" {
  name                         = "${local.name_prefix}-start"
  description                  = "Start environment resources and restore ECS/EKS desired counts."
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.start_schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.scheduler_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.environment_scheduler.arn
    role_arn = aws_iam_role.scheduler_invoke_lambda.arn
    input = jsonencode({
      action = "start"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

resource "aws_scheduler_schedule" "stop" {
  name                         = "${local.name_prefix}-stop"
  description                  = "Scale down ECS/EKS and stop tagged EC2/RDS resources."
  group_name                   = aws_scheduler_schedule_group.this.name
  schedule_expression          = var.stop_schedule_expression
  schedule_expression_timezone = var.schedule_timezone
  state                        = var.scheduler_state

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = aws_lambda_function.environment_scheduler.arn
    role_arn = aws_iam_role.scheduler_invoke_lambda.arn
    input = jsonencode({
      action = "stop"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 2
    }
  }
}

resource "aws_lambda_permission" "allow_scheduler_start" {
  statement_id  = "AllowSchedulerStartInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.environment_scheduler.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.start.arn
}

resource "aws_lambda_permission" "allow_scheduler_stop" {
  statement_id  = "AllowSchedulerStopInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.environment_scheduler.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.stop.arn
}
