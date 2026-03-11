#!/usr/bin/env bash
set -euo pipefail

environment="dev"
chatops_webhook_url=""
itsm_webhook_url=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/configure_approval_webhooks.sh [options]

Options:
  --environment, -Environment <dev|stage|prod>
  --chatops-webhook-url, -ChatOpsWebhookUrl <url>
  --itsm-webhook-url, -ITSMWebhookUrl <url>
  --help, -h
EOF
}

error() {
  echo "Erro: $*" >&2
  exit 1
}

hcl_literal() {
  local value="$1"
  if [[ -z "$value" ]]; then
    echo "null"
    return 0
  fi

  local escaped="$value"
  escaped="${escaped//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '"%s"' "$escaped"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --environment|-Environment)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      environment="$2"
      shift 2
      ;;
    --chatops-webhook-url|-ChatOpsWebhookUrl)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      chatops_webhook_url="$2"
      shift 2
      ;;
    --itsm-webhook-url|-ITSMWebhookUrl)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      itsm_webhook_url="$2"
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

if [[ -z "${chatops_webhook_url// }" && -z "${itsm_webhook_url// }" ]]; then
  error "Informe ao menos um webhook: --chatops-webhook-url e/ou --itsm-webhook-url."
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_file="$repo_root/env/$environment/terraform.local.tfvars"

chatops_literal="$(hcl_literal "$chatops_webhook_url")"
itsm_literal="$(hcl_literal "$itsm_webhook_url")"

cat > "$target_file" <<EOF
# Local-only secrets (do not commit).
approval_bridge_chatops_webhook_url = $chatops_literal
approval_bridge_itsm_webhook_url    = $itsm_literal
EOF

echo "Arquivo atualizado: $target_file"
echo "Use plan/apply com var-file adicional:"
echo "terraform plan  -var-file=../../env/$environment/terraform.tfvars -var-file=../../env/$environment/terraform.local.tfvars"
echo "terraform apply -var-file=../../env/$environment/terraform.tfvars -var-file=../../env/$environment/terraform.local.tfvars"
