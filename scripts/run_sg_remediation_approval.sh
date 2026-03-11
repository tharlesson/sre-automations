#!/usr/bin/env bash
set -euo pipefail

environment="dev"
region="us-east-1"
project="sreauto"
profile=""
dry_run="true"
require_manual_approval="true"
reason="Aprovacao operacional SG remediation"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_sg_remediation_approval.sh [options]

Options:
  --environment, -Environment <dev|stage|prod>
  --region, -Region <aws-region>
  --project, -Project <project-name>
  --profile, -Profile <aws-profile>
  --dry-run, -DryRun <true|false>
  --require-manual-approval, -RequireManualApproval <true|false>
  --reason, -Reason <text>
  --help, -h
EOF
}

error() {
  echo "Erro: $*" >&2
  exit 1
}

normalize_bool() {
  local value
  value="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|false)
      echo "$value"
      ;;
    *)
      error "Valor booleano invalido: $1 (use true|false)"
      ;;
  esac
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment|-Environment)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      environment="$2"
      shift 2
      ;;
    --region|-Region)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      region="$2"
      shift 2
      ;;
    --project|-Project)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      project="$2"
      shift 2
      ;;
    --profile|-Profile)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      profile="$2"
      shift 2
      ;;
    --dry-run|-DryRun)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      dry_run="$2"
      shift 2
      ;;
    --require-manual-approval|-RequireManualApproval)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      require_manual_approval="$2"
      shift 2
      ;;
    --reason|-Reason)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      reason="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      error "Argumento invalido: $1"
      ;;
  esac
done

case "$environment" in
  dev|stage|prod) ;;
  *) error "Environment invalido: $environment" ;;
esac

dry_run="$(normalize_bool "$dry_run")"
require_manual_approval="$(normalize_bool "$require_manual_approval")"

if ! command -v aws >/dev/null 2>&1; then
  error "AWS CLI nao encontrada no PATH."
fi

name_prefix="${project}-${environment}-${region}"
document_name="${name_prefix}-sg-remediation-approval"

temp_parameters_file="$(mktemp)"
cleanup() {
  rm -f "$temp_parameters_file"
}
trap cleanup EXIT

reason_escaped="$(json_escape "$reason")"
cat > "$temp_parameters_file" <<EOF
{"DryRun":["$dry_run"],"RequireManualApproval":["$require_manual_approval"],"Reason":["$reason_escaped"]}
EOF

aws_args=(
  ssm
  start-automation-execution
  --region "$region"
  --document-name "$document_name"
  --parameters "file://$temp_parameters_file"
  --query "AutomationExecutionId"
  --output text
)

if [[ -n "${profile// }" ]]; then
  aws_args+=(--profile "$profile")
fi

automation_execution_id="$(aws "${aws_args[@]}")"

echo "Documento SSM executado: $document_name"
echo "AutomationExecutionId: $automation_execution_id"
