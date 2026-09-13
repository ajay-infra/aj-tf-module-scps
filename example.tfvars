# example.tfvars — CI dry-run plan (no real AWS credentials required)
# Replace all placeholder values with real ones before applying to production.

# Management account (the account that owns AWS Organizations)
management_account_id = "123456789012"

# AWS Organizations root ID — found in Organizations console → Root
org_root_id = "r-ab12"

# Bundle attachment. Guardrails are merged into 4 bundles and attached by OU
# depth, because AWS allows only 5 SCP attachments per entity (FullAWSAccess
# takes one of them). Placeholder OU IDs — CI only plans, never applies.
bundle_attachments = {
  baseline         = ["r-ab12"]
  security-hygiene = ["ou-ab12-platform", "ou-ab12-product", "ou-ab12-saas"]
  data-protection  = ["ou-ab12-platform", "ou-ab12-product", "ou-ab12-saas"]
  # PRODUCT OUs only — `governance` carries require-tags-product, the PRODUCT
  # tagging profile. SaaS is a separate stack whose profile is not yet defined,
  # so ou-ab12-dedicated was removed. See aj-infra-context/arch/tag-profiles.md.
  governance = ["ou-ab12-prod", "ou-ab12-regulated"]
}

# Control accounts — account-model.md v2 §7. Each control OU gets at most two
# direct attachments; security-hygiene and data-protection reach it by
# inheritance from ou-ab12-platform.
platform_bundle_attachments = {
  dns-guard      = ["ou-ab12-dns"]
  registry-guard = ["ou-ab12-registry"]
  control-plane  = ["ou-ab12-security", "ou-ab12-logs", "ou-ab12-dns", "ou-ab12-registry"]
}
# Empty means NOBODY may write the apex zones or delete images. Set these to the
# pipelines' roles before the first delegation / push, not after it is denied.
dns_pipeline_role_arns      = ["arn:aws:iam::777777777777:role/dns-pipeline"]
registry_pipeline_role_arns = ["arn:aws:iam::555555555555:role/registry-pipeline"]

# Regions — deny all API calls outside this list (global services excluded)
allowed_regions = ["us-east-1"]

# All 11 guardrails enabled. These are the *guardrails*, not the bundles —
# each is routed into a bundle by the module. Removing one here drops it from
# whichever bundle contains it.
enabled_policies = [
  "deny-root",
  "deny-leave-org",
  "deny-disable-cloudtrail",
  "deny-iam-users",
  "require-imdsv2",
  "deny-unencrypted-s3",
  "restrict-regions",
  "deny-disable-guardduty",
  "deny-public-s3-acls",
  "require-ebs-encryption",
  "require-tags-product",
  # The SaaS profile. Enabled so the document is created and its size checked
  # at plan time; NOT attached below — no module emits Customer or ProductLine
  # yet, and attaching a tag requirement before the emit side exists denies
  # every create in the OU. See locals.tf, require-tags-saas.
  "require-tags-saas",
  # Control-account guardrails — account-model.md v2 §7.
  "protect-dns",
  "protect-registry",
  "deny-compute",
]

# SOPS KMS keys — one per environment
sops_environments = ["dev", "staging", "prod"]

# ArgoCD Pod Identity role ARNs (fill in once ArgoCD is deployed)
argocd_role_arns = {}

# Engineer roles that can encrypt/decrypt with SOPS locally
engineer_role_arns = []

# KMS key deletion window
kms_deletion_window_days = 30

name_prefix = "aj-infra"
team        = "team-0001" # a team code — aj-infra/envs/org/teams.yaml
cost_center = "infra-2026-q1"
