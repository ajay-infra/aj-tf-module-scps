# ── SCP Outputs ───────────────────────────────────────────────────────────────

output "scp_bundle_ids" {
  description = "Map of bundle name → Organizations policy ID for each created bundle."
  value       = { for name, policy in aws_organizations_policy.scp : name => policy.id }
}

output "scp_bundle_arns" {
  description = "Map of bundle name → Organizations policy ARN for each created bundle."
  value       = { for name, policy in aws_organizations_policy.scp : name => policy.arn }
}

output "bundle_members" {
  description = "Map of bundle name → the guardrails merged into it, after enabled_policies filtering."
  value       = local.bundle_members
}

output "bundle_document_sizes" {
  description = "Map of bundle name → encoded document size in characters. The AWS limit is 5,120."
  value       = { for name, content in local.active_bundles : name => length(content) }
}

output "attachments_per_target" {
  description = <<-EOT
    Map of Organizations target ID → number of SCPs this module attaches to it.
    AWS allows 5 per entity including FullAWSAccess, so 4 is the ceiling here.
    Does not count attachments inherited from parent OUs.
  EOT
  value = {
    for target in distinct([for pair in values(local.bundle_target_pairs) : pair.target_id]) :
    target => length([for pair in values(local.bundle_target_pairs) : pair if pair.target_id == target])
  }
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
