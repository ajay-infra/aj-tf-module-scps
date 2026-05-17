# envs/prod.tfvars — production org values
# Applied ONCE to the management account. All member accounts are covered.
# Applied by: aj-infra-release / provision-org.yml (not yet built)

# Replace with real values from AWS Organizations console
management_account_id = "REPLACE_WITH_MANAGEMENT_ACCOUNT_ID"
org_root_id           = "REPLACE_WITH_ORG_ROOT_ID"

# Start with root — narrows to specific OUs once org structure is defined
target_ou_ids = []

# Primary region only. Add additional regions if the platform expands.
allowed_regions = ["us-east-1"]

# All SCPs enabled in production
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
