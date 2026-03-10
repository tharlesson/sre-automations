# module: automation_backup_validation

Automacao P0 para validacao de backup/restore:
- localiza snapshots recentes
- valida janela de retencao
- tenta restore temporario (quando permitido)
- executa smoke checks
- remove recurso temporario
- gera evidencia em S3
- orquestra com Step Functions