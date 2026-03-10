data "archive_file" "package" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/${var.name}.zip"
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "LambdaTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

locals {
  role_name         = coalesce(var.lambda_role_name, "${var.name}-role")
  create_dlq        = var.dlq_enabled && var.dead_letter_target_arn == null
  effective_dlq_arn = var.dlq_enabled ? coalesce(var.dead_letter_target_arn, try(aws_sqs_queue.dlq[0].arn, null)) : null
}

resource "aws_sqs_queue" "dlq" {
  count = local.create_dlq ? 1 : 0

  name                       = "${var.name}-dlq"
  kms_master_key_id          = var.dlq_kms_key_id
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = var.dlq_kms_key_id == null
  tags                       = var.tags
}

resource "aws_iam_role" "this" {
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = var.iam_policy_json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = var.name
  description   = var.description
  role          = aws_iam_role.this.arn
  handler       = var.handler
  runtime       = var.runtime
  timeout       = var.timeout
  memory_size   = var.memory_size
  architectures = var.architectures
  layers        = var.layers
  kms_key_arn   = var.kms_key_arn
  filename      = data.archive_file.package.output_path
  publish       = var.publish

  source_code_hash = data.archive_file.package.output_base64sha256

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "dead_letter_config" {
    for_each = local.effective_dlq_arn != null ? [1] : []
    content {
      target_arn = local.effective_dlq_arn
    }
  }

  tracing_config {
    mode = var.tracing_mode
  }

  reserved_concurrent_executions = var.reserved_concurrent_executions

  depends_on = [
    aws_cloudwatch_log_group.this,
    aws_iam_role_policy_attachment.basic_execution,
    aws_iam_role_policy.this,
  ]

  tags = var.tags
}

resource "aws_lambda_function_event_invoke_config" "this" {
  function_name                = aws_lambda_function.this.function_name
  maximum_event_age_in_seconds = var.max_event_age_seconds
  maximum_retry_attempts       = var.max_retry_attempts
}
