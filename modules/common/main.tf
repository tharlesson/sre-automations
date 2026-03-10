locals {
  mandatory_tags = {
    Environment = var.environment
    Application = var.application
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = var.managed_by
  }

  tags        = merge(local.mandatory_tags, var.extra_tags)
  name_prefix = "${var.project}-${var.environment}-${var.region}"
}