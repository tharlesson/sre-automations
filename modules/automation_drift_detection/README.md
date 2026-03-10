# module: automation_drift_detection

Automacao P1 para drift detection operacional em recursos criticos:
- Security Groups
- ECS Services
- Listeners
- Parametros SSM
- Tags obrigatorias/criticas

Le baseline de S3 e gera relatorio com alerta SNS.

## Baseline inicial
- Defina `publish_initial_baseline=true` para publicar baseline em `baseline_object_key`.
- Opcionalmente passe `initial_baseline_content` (JSON string).
