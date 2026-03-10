locals {
  provider_default_tags = merge(
    {
      Environment = var.environment
      Application = var.application
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = var.managed_by
    },
    var.extra_tags,
  )
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  dynamic "assume_role" {
    for_each = var.aws_assume_role_arn == null ? [] : [var.aws_assume_role_arn]
    content {
      role_arn     = assume_role.value
      session_name = var.aws_assume_role_session_name
    }
  }

  default_tags {
    tags = local.provider_default_tags
  }
}