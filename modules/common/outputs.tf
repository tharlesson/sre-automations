output "tags" {
  description = "Mandatory and extra tags merged."
  value       = local.tags
}

output "mandatory_tags" {
  description = "Mandatory governance tags."
  value       = local.mandatory_tags
}

output "name_prefix" {
  description = "Prefix in format <project>-<environment>-<region>."
  value       = local.name_prefix
}