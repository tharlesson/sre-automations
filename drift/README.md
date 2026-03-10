Baseline inicial para drift detection.

Como gerar com recursos reais da AWS:
1. Execute o script com perfil/ambiente:
   - `python drift/generate_baseline_from_aws.py --region us-east-1 --profile my-dev-profile --environment dev --application sre-platform --output drift/baseline.initial.json`
2. (Opcional) incluir parametros SSM no baseline:
   - `--ssm-parameter-prefix /sreauto/dev/`

Alternativa com helper PowerShell:
- `./scripts/seed_drift_baseline.ps1 -Environment dev -EnablePublishOnFirstApply`

Publicacao no primeiro apply:
1. No `env/<ambiente>/terraform.tfvars`:
   - `drift_detection_publish_initial_baseline = true`
   - `drift_detection_initial_baseline_file_path = "../../drift/baseline.initial.json"`
2. Execute `terraform apply` no stack do ambiente.

Observacao importante:
- Depois do primeiro apply com baseline publicada, altere para:
  - `drift_detection_publish_initial_baseline = false`
- Isso evita sobrescrever baseline em mudancas operacionais planejadas.
