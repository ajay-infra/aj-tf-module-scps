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

variable "bundle_attachments" {
  type        = map(list(string))
  description = <<-EOT
    Which OUs (or accounts, or the root) each SCP bundle attaches to.
    Keys must be bundle names: baseline, security-hygiene, data-protection, governance.
    Values are Organizations target IDs — r-xxxx, ou-xxxx-yyyyyyyy, or a 12-digit account ID.

    Empty ({}) means minimum viable guardrail: the baseline bundle at org_root_id
    and nothing else.

    AWS caps SCP attachments at 5 per entity and FullAWSAccess consumes one, so
    no single target may appear in more than 4 bundles. This is validated below.
    The quota counts DIRECT attachments only — a bundle attached to a parent OU
    is still evaluated against every account beneath it, but does not consume
    those accounts' slots. Depth is free; breadth at one entity is not.

    Example:
      {
        baseline         = ["r-abcd"]
        security-hygiene = ["ou-abcd-product", "ou-abcd-saas"]
        governance       = ["ou-abcd-prod"]
      }
  EOT
  default     = {}

  validation {
    condition = alltrue([
      for bundle in keys(var.bundle_attachments) :
      contains(["baseline", "security-hygiene", "data-protection", "governance"], bundle)
    ])
    error_message = "bundle_attachments keys must be one of: baseline, security-hygiene, data-protection, governance."
  }

  validation {
    condition = alltrue([
      for target in distinct(flatten(values(var.bundle_attachments))) :
      length([for bundle, targets in var.bundle_attachments : bundle if contains(targets, target)]) <= 4
    ])
    error_message = "A target may appear in at most 4 bundles — AWS allows 5 SCP attachments per entity and FullAWSAccess uses one."
  }
}

# ── SCP Policy Selection ──────────────────────────────────────────────────────

variable "enabled_policies" {
  type        = list(string)
  description = <<-EOT
    SCP policy names to create and attach. Defaults to all 11 guardrails.
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
      require-tags-product            — deny resource creation without Environment, Team, ManagedBy tags
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
    "require-tags-product",
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
