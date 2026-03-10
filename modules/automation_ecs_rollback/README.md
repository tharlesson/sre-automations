# module: automation_ecs_rollback

Automacao P0 de rollback seguro para ECS:
- Step Functions como orquestrador
- lambda worker para descobrir revisao estavel, atualizar servico e validar health
- retries/catches no workflow
- notificacao SNS
- trigger opcional por evento de falha de deploy ECS