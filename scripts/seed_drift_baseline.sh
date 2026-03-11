#!/usr/bin/env bash
set -euo pipefail

environment="dev"
region=""
profile=""
application=""
enable_publish_on_first_apply="false"
ssm_parameter_prefixes=()

usage() {
  cat <<'EOF'
Usage:
  ./scripts/seed_drift_baseline.sh [options]

Options:
  --environment, -Environment <dev|stage|prod>
  --region, -Region <aws-region>
  --profile, -Profile <aws-profile>
  --application, -Application <tag-value>
  --ssm-parameter-prefix, -SsmParameterPrefix <prefix>  (repeatable)
  --enable-publish-on-first-apply, -EnablePublishOnFirstApply
  --help, -h
EOF
}

error() {
  echo "Erro: $*" >&2
  exit 1
}

get_tfvars_string_value() {
  local path="$1"
  local key="$2"
  local line

  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"[^\"]*\"[[:space:]]*$" "$path" | head -n1 || true)"
  if [[ -z "$line" ]]; then
    return 0
  fi

  echo "$line" | sed -E 's/^[^"]*"([^"]*)".*$/\1/'
}

set_tfvars_literal_value() {
  local path="$1"
  local key="$2"
  local literal_value="$3"
  local tmp

  tmp="$(mktemp)"
  awk -v key="$key" -v literal="$literal_value" '
    BEGIN { replaced = 0 }
    {
      if ($0 ~ ("^[[:space:]]*" key "[[:space:]]*=")) {
        print key " = " literal
        replaced = 1
        next
      }
      print
    }
    END {
      if (replaced == 0) {
        print key " = " literal
      }
    }
  ' "$path" > "$tmp"
  mv "$tmp" "$path"
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
    --profile|-Profile)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      profile="$2"
      shift 2
      ;;
    --application|-Application)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      application="$2"
      shift 2
      ;;
    --ssm-parameter-prefix|-SsmParameterPrefix)
      [[ $# -ge 2 ]] || error "Parametro ausente para $1"
      ssm_parameter_prefixes+=("$2")
      shift 2
      ;;
    --enable-publish-on-first-apply|-EnablePublishOnFirstApply)
      enable_publish_on_first_apply="true"
      shift
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

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tfvars_file="$repo_root/env/$environment/terraform.tfvars"
baseline_file="$repo_root/drift/baseline.initial.json"
generator_script="$repo_root/drift/generate_baseline_from_aws.py"

[[ -f "$tfvars_file" ]] || error "Arquivo nao encontrado: $tfvars_file"

if [[ -z "${region// }" ]]; then
  region="$(get_tfvars_string_value "$tfvars_file" "region")"
fi
if [[ -z "${profile// }" ]]; then
  profile="$(get_tfvars_string_value "$tfvars_file" "aws_profile")"
fi
if [[ -z "${application// }" ]]; then
  application="$(get_tfvars_string_value "$tfvars_file" "application")"
fi

[[ -n "${region// }" ]] || error "Nao foi possivel determinar a regiao (region)."

if command -v python3 >/dev/null 2>&1; then
  python_exe="python3"
elif command -v python >/dev/null 2>&1; then
  python_exe="python"
else
  error "Python nao encontrado. Instale python3 (ou python) no PATH."
fi

args=(
  "$generator_script"
  "--region" "$region"
  "--environment" "$environment"
  "--output" "$baseline_file"
)

if [[ -n "${profile// }" ]]; then
  args+=("--profile" "$profile")
fi
if [[ -n "${application// }" ]]; then
  args+=("--application" "$application")
fi

for prefix in "${ssm_parameter_prefixes[@]}"; do
  if [[ -n "${prefix// }" ]]; then
    args+=("--ssm-parameter-prefix" "$prefix")
  fi
done

echo "Gerando baseline real: environment=$environment region=$region profile=$profile"
"$python_exe" "${args[@]}"

if [[ "$enable_publish_on_first_apply" == "true" ]]; then
  set_tfvars_literal_value "$tfvars_file" "drift_detection_publish_initial_baseline" "true"
  set_tfvars_literal_value "$tfvars_file" "drift_detection_initial_baseline_file_path" "\"../../drift/baseline.initial.json\""
  echo "Flags de primeiro apply atualizadas em: $tfvars_file"
fi

echo "Baseline pronta em: $baseline_file"
