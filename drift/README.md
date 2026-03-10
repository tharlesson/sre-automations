Baseline inicial para drift detection.

Como usar:
1. Edite `baseline.initial.json` com os recursos críticos reais.
2. No `env/<ambiente>/terraform.tfvars`, configure:
   - `drift_detection_publish_initial_baseline = true`
   - `drift_detection_initial_baseline_file_path = "../../drift/baseline.initial.json"` (ou outro caminho)
3. Execute `terraform apply` no stack do ambiente.

Observacao:
- Depois de publicado, recomenda-se manter `drift_detection_publish_initial_baseline = false`
  para evitar sobrescrever baseline em mudanças operacionais planejadas.