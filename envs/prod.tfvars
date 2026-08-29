# envs/prod.tfvars — production org values
# Applied ONCE to the management account. All member accounts are covered.
# Applied by: aj-infra-release / .github/workflows/aws/provision-org.yml

# Replace with real values from AWS Organizations console
management_account_id = "REPLACE_WITH_MANAGEMENT_ACCOUNT_ID"
org_root_id           = "REPLACE_WITH_ORG_ROOT_ID"

# Bundle attachment, mapped onto the OU tree in
# aj-infra-context/arch/account-model.md §7. Baseline is universal and sits at
# the root; the rest attach at the shallowest OU they should govern and reach
# member accounts by inheritance. Sandbox appears nowhere below, so it inherits
# baseline only — deliberately.
#
# Max attachments landing on any single entity here: 2. AWS allows 5, of which
# FullAWSAccess consumes 1.
bundle_attachments = {
  baseline         = ["REPLACE_WITH_ORG_ROOT_ID"]
  security-hygiene = ["REPLACE_WITH_OU_PLATFORM", "REPLACE_WITH_OU_PRODUCT", "REPLACE_WITH_OU_SAAS"]
  data-protection  = ["REPLACE_WITH_OU_PLATFORM", "REPLACE_WITH_OU_PRODUCT", "REPLACE_WITH_OU_SAAS"]
  # PRODUCT OUs ONLY. SaaS/Dedicated was here and was wrong — `governance`
  # carries require-tags-product, which encodes the PRODUCT tagging profile.
  # SaaS is a separate stack whose profile is not yet defined
  # (aj-infra-context/arch/tag-profiles.md §5). A SaaS bundle attaches here
  # separately once it exists; until then SaaS is UNENFORCED rather than
  # wrongly enforced, which is the deliberate choice.
  governance = ["REPLACE_WITH_OU_PRODUCT_PROD", "REPLACE_WITH_OU_PRODUCT_REGULATED"]
}

# Primary region only. Add additional regions if the platform expands.
allowed_regions = ["us-east-1"]

# All 11 guardrails enabled in production (these are guardrails, not bundles)
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
]

# SOPS KMS keys
sops_environments = ["dev", "staging", "prod"]

# Fill in once ArgoCD is deployed to each cluster
# argocd_role_arns = {
#   dev     = "arn:aws:iam::DEV_ACCOUNT_ID:role/dev-blue-argocd-runner"
#   staging = "arn:aws:iam::STAGING_ACCOUNT_ID:role/staging-blue-argocd-runner"
#   prod    = "arn:aws:iam::PROD_ACCOUNT_ID:role/prod-blue-argocd-runner"
# }
argocd_role_arns = {}

# Engineer roles — infra-lead role in the management account
# engineer_role_arns = [
#   "arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/infra-lead",
#   "arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/infra-engineer",
# ]
engineer_role_arns = []

kms_deletion_window_days = 30

name_prefix = "aj-infra"
team        = "infra-core"
cost_center = "infra-2026-q1"
