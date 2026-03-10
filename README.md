# AWS SRE Automation Platform (Terraform IaC)

Plataforma de automacoes SRE para AWS, com foco em reducao de toil, governanca, incident response, operacao segura e controle de custos.

Esta base entrega **P0 implementado** e deixa a estrutura pronta para expansao de **P1**.

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
|-- stepfunctions/
|   |-- p0_ecs_rollback.asl.json
|   |-- p0_backup_validation.asl.json
|-- ssm/
|   |-- documents/
|       |-- patching.yaml
|       |-- diagnostics.yaml
|       |-- cleanup_disk.yaml
|       |-- service_restart.yaml
|-- env/
|   |-- dev/
|   |-- stage/
|   |-- prod/
|-- tests/
|   |-- lambdas/
|-- Makefile
|-- requirements-dev.txt
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
Arquivo exemplo: `.github/workflows/terraform-ci.yml.example`
- `terraform fmt -check`
- `terraform validate`
- `terraform plan` por stack

## Testes
Testes minimos em `tests/lambdas` para validar comportamento base dos handlers P0.

```bash
pip install -r requirements-dev.txt
pytest -q tests
```

## Plano de expansao (P1)
A base ja esta preparada para adicionar os modulos abaixo mantendo o mesmo padrao de interface:
1. Patching e runbooks operacionais SSM com janelas e approvals.
2. Remediacao de Security Groups expostos com aprovacao manual.
3. Relatorio FinOps automatizado (JSON/CSV em S3).
4. Drift detection operacional para recursos criticos.

## Notas de design
- Nao foram usados modulos comunitarios genericos para logica principal das automacoes.
- A implementacao privilegia clareza e controle operacional, mantendo composicao por modulos pequenos e reutilizaveis.