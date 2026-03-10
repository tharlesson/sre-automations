# SOP Pos-Apply (P0/P1)

Checklist operacional para validar o ambiente apos `terraform apply`.

## 1. Pre-flight
- Confirmar ambiente e stack (`dev`, `stage`, `prod`).
- Confirmar credenciais AWS ativas (`aws sts get-caller-identity`).
- Confirmar que o apply usou os `tfvars` corretos.

## 2. Validar estado Terraform
1. `cd stacks/<env>`
2. `terraform output`
3. Salvar evidencias:
   - `name_prefix`
   - `automation_alerts_topic_arn`
   - `approval_requests_topic_arn`
   - `drift_detection_baseline_s3_uri`
   - `sg_exposure_remediation_state_machine_arn`

## 3. Validar baseline de drift
1. Conferir se o objeto baseline existe:
   - `aws s3 ls <drift_detection_baseline_s3_uri>`
2. Se o primeiro apply usou seed:
   - garantir em `env/<env>/terraform.tfvars`:
     - `drift_detection_publish_initial_baseline = false`
3. Rodar novo `terraform plan` para garantir sem sobrescrita indesejada.

## 4. Validar agendamentos/EventBridge
- Conferir regras/schedules ativos para automacoes P0/P1.
- Validar timezone e `schedule_expression` por ambiente.
- Garantir automacoes criticas habilitadas conforme politica operacional.

## 5. Validar Lambdas e Step Functions
- Conferir status e logs de primeira execucao:
  - `scheduler`
  - `tag_auditor`
  - `cert_secret_monitor`
  - `orphan_cleanup`
  - `incident_evidence`
  - `finops_report`
  - `drift_detection`
  - `approval_bridge`
- Conferir state machines:
  - ECS rollback
  - backup validation
  - SG remediation

## 6. Validar alertas e observabilidade
- Conferir alarmes CloudWatch de falha Lambda e Step Functions.
- Publicar evento de teste em SNS `automation_alerts` e verificar assinatura.

## 7. Validar aprovacoes (SG remediation)
1. Executar runbook:
   - `./scripts/run_sg_remediation_approval.ps1 -Environment <env> -Region <region> -Project <project> -Profile <profile>`
2. Confirmar:
   - execucao SSM criada
   - execucao Step Functions criada
   - notificacao no SNS de aprovacao
   - entrega em ChatOps/ITSM (quando webhook configurado)

## 8. Validar webhooks approval bridge
1. Criar `env/<env>/terraform.local.tfvars` via:
   - `./scripts/configure_approval_webhooks.ps1 ...`
2. Aplicar stack com `-var-file` adicional local.
3. Publicar mensagem de aprovacao no topico `approval_requests` e validar recebimento.

## 9. Encerramento
- Registrar evidencias (output, ids de execucao, links de logs).
- Registrar riscos pendentes e plano de correcao.
- Confirmar handoff para operacao/plantao.
