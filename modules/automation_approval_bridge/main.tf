locals {
  lambda_name = "${var.name_prefix}-approval-bridge"

  lambda_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCallerIdentity"
        Effect = "Allow"
        Action = [
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  }
}

module "lambda" {
  source = "../lambda_automation"

  name                  = local.lambda_name
  description           = "Forward approval notifications from SNS to ChatOps/ITSM webhooks."
  source_dir            = var.lambda_source_dir
  handler               = "handler.lambda_handler"
  timeout               = var.lambda_timeout
  memory_size           = var.lambda_memory_size
  log_retention_days    = var.log_retention_days
  iam_policy_json       = jsonencode(local.lambda_policy)
  max_retry_attempts    = 1
  max_event_age_seconds = 3600
  tracing_mode          = "PassThrough"
  dlq_enabled           = false
  tags                  = var.tags

  environment_variables = {
    CHATOPS_WEBHOOK_URL            = coalesce(var.chatops_webhook_url, "")
    ITSM_WEBHOOK_URL               = coalesce(var.itsm_webhook_url, "")
    FORWARD_ONLY_APPROVAL_MESSAGES = tostring(var.forward_only_approval_messages)
    HTTP_TIMEOUT_SECONDS           = tostring(var.http_timeout_seconds)
  }
}

resource "aws_sns_topic_subscription" "lambda" {
  count = var.enabled ? 1 : 0

  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = module.lambda.function_arn
}

resource "aws_lambda_permission" "allow_sns" {
  count = var.enabled ? 1 : 0

  statement_id  = "AllowSnsInvokeApprovalBridge"
  action        = "lambda:InvokeFunction"
  function_name = module.lambda.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}
