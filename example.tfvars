# example.tfvars — CI dry-run plan (no real AWS credentials required)
# Replace all placeholder values with real ones before applying to production.

# Management account (the account that owns AWS Organizations)
management_account_id = "123456789012"

# AWS Organizations root ID — found in Organizations console → Root
org_root_id = "r-ab12"

# Attach SCPs to the org root (covers all accounts).
# Scope to specific OUs once the org structure matures.
target_ou_ids = []

# Regions — deny all API calls outside this list (global services excluded)
allowed_regions = ["us-east-1"]

# All 10 SCPs enabled by default
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
team        = "infra-core"
cost_center = "infra-2026-q1"
