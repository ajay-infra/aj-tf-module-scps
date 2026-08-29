# ── Service Control Policies ──────────────────────────────────────────────────
# Applied once at the org level — enforced regardless of IAM policies.
#
# Policy CREATION and policy ATTACHMENT are deliberately separate. Organizations
# policy names are unique org-wide, so each bundle is created exactly once, in
# one state, and then attached to as many OUs as needed. Running this module
# once per OU would collide on the second apply.

resource "aws_organizations_policy" "scp" {
  for_each = local.active_bundles

  name        = "${var.name_prefix}-${each.key}"
  description = "Guardrail bundle: ${join(", ", local.bundle_members[each.key])}"
  content     = each.value
  type        = "SERVICE_CONTROL_POLICY"

  tags = local.full_tags

  lifecycle {
    # AWS rejects SCP documents over 5,120 characters. Whitespace is not
    # counted, and jsonencode emits none, so length() is the real measure.
    # Caught at plan time rather than as a mid-apply API error.
    # A stale or misspelled name in enabled_policies silently removes a
    # guardrail rather than failing. Checked here so a typo is a plan error
    # instead of a missing control.
    precondition {
      condition     = length(local.unknown_enabled_policies) == 0
      error_message = "enabled_policies contains names matching no guardrail: ${join(", ", local.unknown_enabled_policies)}. A stale name silently empties its bundle and removes the guardrail with no error. Known guardrails: ${join(", ", sort(keys(local.scp_statements)))}."
    }

    precondition {
      condition     = length(each.value) <= 5120
      error_message = "SCP bundle '${each.key}' is ${length(each.value)} characters, over the 5,120 limit. Split it or move a guardrail to another bundle."
    }
  }
}

# Attach each created bundle to every target named for it in bundle_attachments.
resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.bundle_target_pairs

  policy_id = aws_organizations_policy.scp[each.value.bundle].id
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
