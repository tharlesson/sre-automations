# module: automation_sg_exposure_remediation

Automacao P1 para remediacao de Security Groups expostos:
- detecta portas criticas abertas para 0.0.0.0/0 e ::/0
- workflow Step Functions com gate de aprovacao manual
- remediacao opcional e controlada por flags
- dry-run suportado
- suporte a topico SNS dedicado para pedidos de aprovacao
