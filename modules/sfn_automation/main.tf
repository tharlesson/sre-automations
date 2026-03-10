data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "StepFunctionsTrust"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "${var.name}-policy"
  role   = aws_iam_role.this.id
  policy = var.iam_policy_json
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/vendedlogs/states/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = aws_iam_role.this.arn
  type       = var.state_machine_type
  definition = templatefile(var.definition_path, var.definition_vars)

  logging_configuration {
    include_execution_data = true
    level                  = "ALL"

    log_destination = "${aws_cloudwatch_log_group.this.arn}:*"
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  depends_on = [aws_iam_role_policy.this]

  tags = var.tags
}