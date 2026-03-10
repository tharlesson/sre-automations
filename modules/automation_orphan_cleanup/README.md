# module: automation_orphan_cleanup

Automacao P0 para limpeza controlada de recursos orfaos:
- snapshots antigos
- EBS volumes orfaos
- ENIs orfas
- Elastic IPs sem uso
- imagens antigas no ECR
- log groups antigos

Suporta modo relatorio (`dry_run=true`) e modo execucao protegido por flag explicita.