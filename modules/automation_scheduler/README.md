# module: automation_scheduler

Automacao P0 para start/stop de ambiente nao produtivo:
- EC2, RDS, ECS e ASG
- filtros por tag
- EventBridge Scheduler
- Lambda com suporte opcional a SSM antes de parar EC2
- persistencia de desired counts em S3 para restore seguro