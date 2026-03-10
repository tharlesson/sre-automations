# module: lambda_automation

Padroniza deploy de Lambda com:
- zip via `archive_file`
- IAM role + policy inline
- CloudWatch Logs com retention configuravel
- DLQ opcional (SQS)
- retries/TTL de invocacao assincrona

## Inputs principais
- `name`
- `source_dir`
- `iam_policy_json`
- `environment_variables`

## Outputs
- `function_name`, `function_arn`, `role_arn`, `dlq_arn`