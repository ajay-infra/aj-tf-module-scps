# ── Service Control Policies ──────────────────────────────────────────────────
# Applied once at the org level — enforced regardless of IAM policies.
# Enabled policies and attachment targets are controlled via variables.

resource "aws_organizations_policy" "scp" {
  for_each = local.active_policies

  name        = "${var.name_prefix}-${each.key}"
  description = "Guardrail: ${each.key}"
  content     = each.value
  type        = "SERVICE_CONTROL_POLICY"

  tags = local.full_tags
}

# Attach each enabled policy to every target (root OU or specific OUs)
resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.policy_target_pairs

  policy_id = aws_organizations_policy.scp[each.value.policy_name].id
  target_id = each.value.target_id
}

# ── KMS Keys for SOPS ─────────────────────────────────────────────────────────
# One key per environment. ArgoCD uses these keys (via ksops plugin) to decrypt
# SOPS-encrypted Helm values and K8s secret manifests at render time.
#
# Key policy grants:
#   - Management account root: full key administration
#   - ArgoCD Pod Identity role (per env): Decrypt only (ksops render path)
#   - Engineer roles: Encrypt + Decrypt (sops -e locally, sops -d for debugging)

resource "aws_kms_key" "sops" {
  for_each = toset(var.sops_environments)

  description             = local.sops_key_descriptions[each.key]
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid    = "KeyAdminManagementAccount"
          Effect = "Allow"
          Principal = {
            AWS = "arn:aws:iam::${var.management_account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        },
      ],

      # ArgoCD decrypt — only if role ARN is provided for this environment
      lookup(var.argocd_role_arns, each.key, "") != "" ? [
        {
          Sid    = "ArgoCDKsopsDecrypt"
          Effect = "Allow"
          Principal = {
            AWS = var.argocd_role_arns[each.key]
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
          ]
          Resource = "*"
        }
      ] : [],

      # Engineer encrypt + decrypt — only if role ARNs are provided
      length(var.engineer_role_arns) > 0 ? [
        {
          Sid    = "EngineersEncryptDecrypt"
          Effect = "Allow"
          Principal = {
            AWS = var.engineer_role_arns
          }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:Encrypt",
            "kms:GenerateDataKey*",
            "kms:ReEncrypt*",
          ]
          Resource = "*"
        }
      ] : [],
    )
  })

  tags = merge(local.full_tags, {
    Environment = each.key
    Purpose     = "sops-encryption"
  })
}

resource "aws_kms_alias" "sops" {
  for_each = toset(var.sops_environments)

  name          = "alias/sops-${each.key}"
  target_key_id = aws_kms_key.sops[each.key].key_id
}
