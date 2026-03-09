# Automacao Lambda - Start/Stop de Ambiente AWS

Este projeto cria uma automacao com AWS Lambda + AWS Scheduler para ligar e desligar ambiente em horarios pre-definidos.

## O que esta implementado

- `stop`:
  - Para EC2 com tag `shutdown=true`.
  - Para RDS (instancias e clusters) com tag `shutdown=true`.
  - ECS: salva quantidade efetiva em `running` por service e escala para `0`.
  - EKS: salva quantidade efetiva em `running` (ready/available) por Deployment e escala para `0`.
- `start`:
  - Inicia EC2 e RDS com tag `shutdown=true`.
  - Le o estado salvo.
  - Restaura ECS/EKS para os valores salvos.

Persistencia de estado padrao: S3 (`state.json`).

## Estrutura

- `lambda/src/handler.py`: codigo da Lambda em Python.
- `iac/`: Terraform (IaC) para bucket de estado, IAM, Lambda e Scheduler.

## Reuso dos modulos existentes

O IaC reaproveita o modulo ja construido:

- `git::https://github.com/tharlesson/terraform-modules.git//modules/s3`

Ele e usado para criar o bucket de estado com guardrails de seguranca.

## Terraform - como usar

1. Ajuste `iac/terraform.tfvars.example` e salve como `iac/terraform.tfvars`.
2. Configure backend remoto em `iac/backend.hcl` (se necessario).
3. Execute:

```bash
cd iac
terraform init -reconfigure -backend-config=backend.hcl
terraform plan
terraform apply
```

## Variaveis principais

- `start_schedule_expression`: horario de ligar.
- `stop_schedule_expression`: horario de desligar.
- `schedule_timezone`: timezone do scheduler.
- `state_bucket_name`: bucket S3 de estado (ou `null` para nome automatico).
- `state_object_key`: caminho do estado JSON.
- `state_access_log_bucket_name`: bucket alvo para server access logs do bucket de estado (`null` usa o proprio bucket de estado).
- `state_access_log_prefix`: prefixo dos access logs.
- `eks_excluded_namespaces`: namespaces ignorados no EKS.
- `dry_run`: executa sem alterar recursos, apenas log.

## Formato de evento da Lambda

Scheduler chama a Lambda com:

```json
{"action":"start"}
```

ou

```json
{"action":"stop"}
```

## Opcoes para salvar estado

1. S3 (implementado neste projeto)
   - Pratico, barato, simples de versionar.
   - Bom para payload JSON maior.
2. DynamoDB
   - Melhor para consulta por chave, concorrencia e lock.
   - Bom quando ha muitas operacoes e atualizacao frequente.
3. SSM Parameter Store
   - Simples para estado pequeno.
   - Limite de tamanho e nao ideal para JSON grande.
4. AWS Secrets Manager
   - Indicado se estado tiver dados sensiveis.
   - Custo maior para este caso.
5. RDS (tabela de estado)
   - Flexivel para historico e consultas SQL.
   - Exige operacao de banco (overhead).
6. ElastiCache/Redis
   - Muito rapido, util para estado temporario.
   - Nao ideal como fonte primaria de estado duravel sem estrategia de persistencia.

## Observacoes importantes

- ECS: restauracao esta orientada a `services` (nao a tarefas avulsas executadas com `run-task`).
- EKS: Lambda precisa ter permissao de acesso ao cluster Kubernetes (RBAC/aws-auth ou Access Entry).
- Se endpoint do EKS for privado, a Lambda deve estar na VPC com rota para o cluster.
