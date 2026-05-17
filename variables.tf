# ── Core ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "name_prefix" {
  type        = string
  description = "Prefix applied to all SCP and KMS resource names."
  default     = "aj-infra"
}

# ── AWS Organizations ─────────────────────────────────────────────────────────

variable "management_account_id" {
  type        = string
  description = "AWS management account ID — used in KMS key policies. Must be a 12-digit string."
}

variable "org_root_id" {
  type        = string
  description = <<-EOT
    AWS Organizations root ID (format: r-xxxx).
    Found in AWS Organizations console → Root.
    SCPs are attached here unless target_ou_ids is specified.
  EOT
}

variable "target_ou_ids" {
  type        = list(string)
  description = <<-EOT
    OU IDs to attach SCPs to. Defaults to the org root (org_root_id).
    Format: ["ou-xxxx-yyyyyyyy", ...]
    Start with root for full coverage, then narrow to specific OUs as the org matures.
  EOT
  default     = []
}

# ── SCP Policy Selection ──────────────────────────────────────────────────────

variable "enabled_policies" {
  type        = list(string)
  description = <<-EOT
    SCP policy names to create and attach. Defaults to all 10 guardrails.
    Remove a name from this list to skip that policy (e.g. during initial rollout).
    Available policies:
      deny-root               — prevent root user from taking any action
      deny-leave-org          — prevent accounts from leaving the organization
      deny-disable-cloudtrail — prevent disabling or deleting CloudTrail
      deny-iam-users          — prevent IAM user creation (force SSO / role-based access)
      require-imdsv2          — block EC2 instances launched without IMDSv2
      deny-unencrypted-s3     — deny S3 PutObject without server-side encryption
      restrict-regions        — deny AWS API calls outside allowed_regions
      deny-disable-guardduty  — prevent disabling or deleting GuardDuty detectors
      deny-public-s3-acls     — deny public-read/public-read-write S3 ACLs
      require-ebs-encryption  — deny EC2 launch with unencrypted EBS volumes
  EOT
  default = [
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
}

variable "allowed_regions" {
  type        = list(string)
  description = "AWS regions to allow. All other regions are denied by the restrict-regions SCP."
  default     = ["us-east-1"]
}

# ── KMS Keys for SOPS ────────────────────────────────────────────────────────

variable "sops_environments" {
  type        = list(string)
  description = "Environments for which SOPS KMS keys are created. One key per environment."
  default     = ["dev", "staging", "prod"]
}

variable "argocd_role_arns" {
  type        = map(string)
  description = <<-EOT
    Map of environment → ArgoCD Pod Identity IAM role ARN.
    ArgoCD uses these roles (via ksops) to decrypt SOPS-encrypted secrets at render time.
    Leave empty ({}) to skip ArgoCD decrypt grants — add them once ArgoCD is deployed.
    Example: { dev = "arn:aws:iam::111111111111:role/dev-argocd-runner" }
  EOT
  default     = {}
}

variable "engineer_role_arns" {
  type        = list(string)
  description = <<-EOT
    IAM role ARNs that engineers use to encrypt secrets with SOPS locally.
    These roles get Encrypt + Decrypt on all SOPS KMS keys.
    Example: ["arn:aws:iam::123456789012:role/infra-engineer"]
  EOT
  default     = []
}

variable "kms_deletion_window_days" {
  type        = number
  description = "KMS key deletion window in days (7-30). Keys scheduled for deletion can be recovered within this window."
  default     = 30
}

# ── Tags ──────────────────────────────────────────────────────────────────────

variable "team" {
  type    = string
  default = "infra-core"
}

variable "cost_center" {
  type    = string
  default = "infra-2026-q1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
