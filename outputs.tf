# ── SCP Outputs ───────────────────────────────────────────────────────────────

output "scp_policy_ids" {
  description = "Map of policy name → Organizations policy ID for all enabled SCPs."
  value       = { for name, policy in aws_organizations_policy.scp : name => policy.id }
}

output "scp_policy_arns" {
  description = "Map of policy name → Organizations policy ARN for all enabled SCPs."
  value       = { for name, policy in aws_organizations_policy.scp : name => policy.arn }
}

output "enabled_policy_names" {
  description = "List of SCP policy names that were created."
  value       = keys(local.active_policies)
}

# ── KMS SOPS Outputs ──────────────────────────────────────────────────────────

output "sops_kms_key_ids" {
  description = "Map of environment → KMS key ID. Reference in .sops.yaml creation_rules."
  value       = { for env, key in aws_kms_key.sops : env => key.key_id }
}

output "sops_kms_key_arns" {
  description = "Map of environment → KMS key ARN. Use in .sops.yaml creation_rules kms field."
  value       = { for env, key in aws_kms_key.sops : env => key.arn }
}

output "sops_kms_aliases" {
  description = "Map of environment → KMS alias ARN (alias/sops-<env>)."
  value       = { for env, alias in aws_kms_alias.sops : env => alias.arn }
}
