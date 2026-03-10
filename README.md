# AWS SRE Automation Platform (Terraform IaC)

Plataforma de automacoes SRE para AWS, com foco em reducao de toil, governanca, incident response, operacao segura e controle de custos.

Esta base entrega **P0 + P1 implementados** com padrao modular e pronto para expansao adicional.

## Objetivos atendidos
- Terraform `>= 1.6`, modular e reutilizavel.
- Multi-ambiente (`dev`, `stage`, `prod`) com `tfvars` e backend remoto (`S3 + DynamoDB lock`).
- Lambdas em Python com logging estruturado, retries e tratamento de erro.
- Step Functions com retries/catches/branching para workflows criticos.
- EventBridge Scheduler e EventBridge Rules com enable/disable por automacao.
- IAM least privilege por automacao.
- Dry-run e flags explicitas para acoes destrutivas.
- Tags obrigatorias em todos os recursos aplicaveis:
  - `Environment`
  - `Application`
  - `Owner`
  - `CostCenter`
  - `ManagedBy=Terraform`
- Naming padrao: `<project>-<environment>-<region>-<resource>`

## Estrutura do repositorio

```text
.
|-- modules/
|   |-- common/
|   |-- lambda_automation/
|   |-- eventbridge_schedule/
|   |-- sfn_automation/
|   |-- observability/
|   |-- automation_scheduler/
|   |-- automation_tag_auditor/
|   |-- automation_cert_secret_monitor/
|   |-- automation_orphan_cleanup/
|   |-- automation_incident_evidence/
|   |-- automation_ecs_rollback/
|   |-- automation_backup_validation/
|   |-- automation_ssm_runbooks/
|   |-- automation_sg_exposure_remediation/
|   |-- automation_finops_report/
|   |-- automation_drift_detection/
|   |-- automation_approval_bridge/
|-- stacks/
|   |-- dev/
|   |-- stage/
|   |-- prod/
|-- lambdas/
|   |-- common/
|   |-- p0_environment_scheduler/
|   |-- p0_tag_auditor/
|   |-- p0_cert_secret_monitor/
|   |-- p0_orphan_cleanup/
|   |-- p0_incident_evidence/
|   |-- p0_ecs_rollback/
|   |-- p0_backup_validation/
|   |-- p1_ssm_runbooks/
|   |-- p1_sg_exposure_remediation/
|   |-- p1_finops_report/
|   |-- p1_drift_detection/
|   |-- p1_approval_bridge/
|-- stepfunctions/
|   |-- p0_ecs_rollback.asl.json
|   |-- p0_backup_validation.asl.json
|   |-- p1_sg_exposure_remediation.asl.json
|-- ssm/
|   |-- documents/
|       |-- patching.yaml
|       |-- diagnostics.yaml
|       |-- cleanup_disk.yaml
|       |-- service_restart.yaml
|       |-- sg_remediation_approval.yaml.tmpl
|-- drift/
|   |-- baseline.initial.json
|   |-- README.md
|   |-- generate_baseline_from_aws.py
|-- scripts/
|   |-- seed_drift_baseline.ps1
|   |-- configure_approval_webhooks.ps1
|   |-- run_sg_remediation_approval.ps1
|-- env/
|   |-- dev/
|   |-- stage/
|   |-- prod/
|-- tests/
|   |-- lambdas/
|   |-- tools/
|-- runbooks/
|   |-- post-apply-sop.md
|-- Makefile
|-- requirements-dev.txt
|-- .github/workflows/terraform-ci.yml
|-- .github/workflows/terraform-ci.yml.example
```

## Automacoes P0 entregues

### 1) Scheduler de ambientes nao produtivos
- Start/stop de EC2 e RDS.
- Scale down/restore de ECS services.
- Scale down/restore de Auto Scaling Groups.
- Filtro por tags (`scheduler_tag_selector`).
- Agendamento por EventBridge Scheduler.
- Lambda com suporte opcional a SSM pre-stop em EC2.

### 2) Auditoria de tags obrigatorias
- Detecta recursos sem tags obrigatorias.
- Alerta via SNS.
- Opcao de auto-remediacao (`AUTO_REMEDIATE`) com dry-run.

### 3) Monitor de certificados e secrets
- Verifica certificados ACM proximos da expiracao.
- Verifica secrets com rotacao proxima ou em estado problematico.
- Alerta via SNS.

### 4) Limpeza controlada de recursos orfaos
- Snapshots antigos.
- EBS volumes orfaos.
- ENIs orfas.
- Elastic IPs sem uso.
- Imagens ECR antigas (untagged).
- Log groups antigos.
- Modo relatorio (`dry_run=true`) e execucao protegida por flag.

### 5) Coletor de evidencias para incidentes
- Trigger por evento de alarme (EventBridge Rule).
- Coleta:
  - contexto do alarme e metricas
  - logs recentes
  - eventos ECS/EKS
  - status de target groups
  - eventos recentes de deploy
- Salva JSON em S3 e notifica via SNS.

### 6) Workflow de rollback ECS (Step Functions)
- Descobre revisao anterior estavel.
- Atualiza ECS service com rollback.
- Aguarda estabilizacao com retries controlados.
- Valida health checks (target groups).
- Notifica sucesso/falha via SNS.

### 7) Validacao de backup e restore (Step Functions)
- Descobre snapshot mais recente.
- Valida janela de retencao.
- Restore temporario (quando permitido por flag).
- Smoke test.
- Cleanup do recurso temporario.
- Evidencia em S3 + notificacao SNS.

## Automacoes P1 entregues

### 8) Patching e runbooks operacionais com SSM
- Janela de patching e janela de runbook operacional com schedules independentes.
- Aprovacao manual opcional antes de executar `SendCommand`.
- Suporte a selecao de targets por tag.
- Reuso dos documentos SSM versionados no repositorio.

### 9) Remediacao de Security Groups expostos
- Deteccao de portas criticas abertas para `0.0.0.0/0` e `::/0`.
- Workflow Step Functions com gate de aprovacao manual.
- Remediacao opcional e controlada por flags de seguranca.
- Runbook SSM Automation para aprovacao operacional com `approved=true`.

### 10) Relatorio FinOps automatizado
- Custo por conta.
- Custo por servico.
- Custo por tags.
- Top desperdicios por heuristicas avancadas:
  - servicos com alto custo
  - custos sem tag
  - Savings Plans subutilizados
  - Reserved Instances subutilizados
  - oportunidades de rightsizing (Compute Optimizer)
- Saida em JSON e CSV no S3.

### 11) Drift detection operacional
- Verificacao de drift em Security Groups, ECS Services, Listeners, parametros SSM e tags.
- Comparacao contra baseline em S3.
- Relatorio estruturado com alerta SNS.
- Upload opcional de baseline inicial via Terraform.

### 12) Integracao de aprovacoes com ChatOps/ITSM
- Topico SNS dedicado para requisicoes de aprovacao.
- Bridge Lambda para encaminhar eventos de aprovacao para webhooks.
- Suporte a canal ChatOps e ITSM simultaneamente.

## Requisitos
- Terraform >= 1.6
- AWS CLI autenticada com perfil/role valida
- Python 3.11+ (para testes locais)

## Deploy por ambiente

### 1. Ajustar backend remoto
Edite os arquivos:
- `env/dev/backend.hcl`
- `env/stage/backend.hcl`
- `env/prod/backend.hcl`

Com:
- bucket S3 de state
- tabela DynamoDB de lock
- chave por ambiente

### 2. Ajustar variaveis por ambiente
Edite:
- `env/dev/terraform.tfvars`
- `env/stage/terraform.tfvars`
- `env/prod/terraform.tfvars`

Opcional (segredos locais, sem commit):
- copie `env/<ambiente>/terraform.local.tfvars.example` para `env/<ambiente>/terraform.local.tfvars`
- preencha `approval_bridge_chatops_webhook_url` e/ou `approval_bridge_itsm_webhook_url`

### 3. Inicializar e aplicar

```bash
# dev
cd stacks/dev
terraform init -reconfigure -backend-config=../../env/dev/backend.hcl
terraform plan  -var-file=../../env/dev/terraform.tfvars
terraform apply -var-file=../../env/dev/terraform.tfvars

# stage
cd ../stage
terraform init -reconfigure -backend-config=../../env/stage/backend.hcl
terraform plan  -var-file=../../env/stage/terraform.tfvars
terraform apply -var-file=../../env/stage/terraform.tfvars

# prod
cd ../prod
terraform init -reconfigure -backend-config=../../env/prod/backend.hcl
terraform plan  -var-file=../../env/prod/terraform.tfvars
terraform apply -var-file=../../env/prod/terraform.tfvars
```

Com webhooks locais:

```bash
terraform plan  -var-file=../../env/dev/terraform.tfvars -var-file=../../env/dev/terraform.local.tfvars
terraform apply -var-file=../../env/dev/terraform.tfvars -var-file=../../env/dev/terraform.local.tfvars
```

## Comandos utilitarios

```bash
make fmt
make validate STACK=dev
make plan STACK=dev
make apply STACK=dev
make test
```

## Seguranca e operacao
- IAM least privilege por automacao (roles dedicadas).
- Log retention configuravel.
- S3 com criptografia e bloqueio de acesso publico onde aplicavel.
- DLQ para Lambdas (modulo `lambda_automation`).
- Dry-run por padrao nas automacoes destrutivas/sensiveis.
- Flags obrigatorias para habilitar acoes destrutivas (`allow_destructive_actions`, `allow_restore`).

## Observabilidade
- SNS central para alertas (`automation_alerts`).
- Alarmes baseline para:
  - `AWS/Lambda` metric `Errors`
  - `AWS/States` metric `ExecutionsFailed`

## CI sugerido
Workflow ativo: `.github/workflows/terraform-ci.yml`
- `terraform fmt -check`
- `terraform validate`
- `terraform plan` por stack
- `pytest -q tests`

## Testes
Testes minimos em `tests/lambdas` para validar comportamento base dos handlers P0/P1.
Inclui tambem testes utilitarios em `tests/tools`.

```bash
pip install -r requirements-dev.txt
pytest -q tests
```

## Runbooks operacionais
- SOP de validacao pos-apply: `runbooks/post-apply-sop.md`

## Proximos passos sugeridos
1. Gerar baseline real:
   - `./scripts/seed_drift_baseline.ps1 -Environment dev -EnablePublishOnFirstApply`
2. Configurar webhooks de aprovacao:
   - `./scripts/configure_approval_webhooks.ps1 -Environment dev -ChatOpsWebhookUrl "<url>" -ITSMWebhookUrl "<url>"`
3. Rodar primeiro apply (com baseline publish em `true`):
   - `terraform apply -var-file=../../env/dev/terraform.tfvars -var-file=../../env/dev/terraform.local.tfvars`
4. Executar runbook SSM de aprovacao operacional:
   - `./scripts/run_sg_remediation_approval.ps1 -Environment dev -Region us-east-1 -Project sreauto -Profile my-dev-profile -DryRun $true`
5. Depois do primeiro apply, retornar:
   - `drift_detection_publish_initial_baseline = false` no `env/dev/terraform.tfvars`

## Notas de design
- Nao foram usados modulos comunitarios genericos para logica principal das automacoes.
- A implementacao privilegia clareza e controle operacional, mantendo composicao por modulos pequenos e reutilizaveis.
