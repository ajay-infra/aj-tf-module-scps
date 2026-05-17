# aj-tf-module-scps

Terraform module for AWS Organizations Service Control Policies (SCPs) and SOPS KMS keys. L0 in the platform stack — applied once to the management account, enforced across all member accounts regardless of IAM.

---

## What this module does

**SCPs** are organization-level guardrails that override IAM policies. Even an account administrator cannot bypass an SCP denial. This module provisions 10 guardrail policies and attaches them to the org root (or specific OUs).

**SOPS KMS keys** (one per environment) encrypt secrets committed to `k8s-manifests`. ArgoCD decrypts them at render time via the ksops plugin. These keys live in the management account and their policy grants Decrypt to ArgoCD's Pod Identity role in each cluster.

Both resources are management-plane — provisioned once, before any cluster or workload exists.

---

## Apply order

This is **Stage 0** — it runs before everything else, in the management account:

```
Stage 0:  aj-tf-module-scps     ← this module (management account)
            → SCPs applied to org root — all member accounts protected
            → KMS keys created — SOPS encryption ready for k8s-manifests

Stage 1+: All other modules run in member accounts (dev/staging/prod)
            → SCPs are already enforced in those accounts
            → ArgoCD in each cluster uses the SOPS KMS key to decrypt secrets
```

This module is applied **once** via `provision-org.yml` in `aj-infra-release` (not per-cluster). Re-apply only when adding new SCPs or updating KMS key policies.

---

## The 10 guardrail policies

| Policy | What it blocks | Why |
|---|---|---|
| `deny-root` | Any action by the root user | Root is a break-glass account only; all daily ops use roles |
| `deny-leave-org` | `organizations:LeaveOrganization` | Prevents rogue accounts from escaping guardrails |
| `deny-disable-cloudtrail` | Deleting, stopping, or updating CloudTrail | Audit trail must be immutable |
| `deny-iam-users` | Creating IAM users or access keys | All human access via IAM Identity Center (SSO); machines use roles |
| `require-imdsv2` | EC2 launch without `HttpTokens=required` | IMDSv1 is exploitable via SSRF — blocks it on all EKS nodes too |
| `deny-unencrypted-s3` | `s3:PutObject` without SSE header | All objects encrypted at rest (KMS or AES256) |
| `restrict-regions` | Any API call outside `allowed_regions` | Prevents shadow infrastructure in unmonitored regions |
| `deny-disable-guardduty` | Deleting or disassociating GuardDuty | Threat detection stays on in every account |
| `deny-public-s3-acls` | Public-read / public-read-write ACLs | Belt-and-suspenders alongside S3 Block Public Access |
| `require-ebs-encryption` | EC2 launch with unencrypted EBS volumes | All persistent storage encrypted at rest |

Each policy is individually toggleable via `enabled_policies`. Start with all 10 — disable only if a specific policy blocks a legitimate use case (document why).

---

## SOPS KMS keys

One KMS key per environment (`dev`, `staging`, `prod`). Alias: `alias/sops-<env>`.

```
Engineer laptop
  sops -e secret.yaml
    → calls KMS Encrypt (engineer_role_arns)
    → encrypted file committed to k8s-manifests

ArgoCD render time
  ksops plugin decrypts SOPS file
    → calls KMS Decrypt (argocd_role_arns[env])
    → plaintext Helm values passed to renderer
    → never stored in ArgoCD state
```

Key policy grants:
- **Management account root** — full key administration
- **ArgoCD Pod Identity role** (per env) — `Decrypt` + `DescribeKey` only
- **Engineer IAM roles** — `Encrypt`, `Decrypt`, `GenerateDataKey`, `ReEncrypt`

---

## How aj-infra-release uses this module

```bash
# provision-org.yml — runs once in the management account
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="key=org/scps/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=${TF_LOCK_TABLE}"

terraform apply -var-file=envs/prod.tfvars
```

KMS key ARNs from `sops_kms_key_arns` output are then written into `.sops.yaml` in `k8s-manifests`:

```yaml
# k8s-manifests/.sops.yaml
creation_rules:
  - path_regex: envs/dev/.*\.yaml
    kms: arn:aws:kms:us-east-1:DEV_ACCOUNT:key/<dev-key-id>
  - path_regex: envs/staging/.*\.yaml
    kms: arn:aws:kms:us-east-1:STAGING_ACCOUNT:key/<staging-key-id>
  - path_regex: envs/prod/.*\.yaml
    kms: arn:aws:kms:us-east-1:PROD_ACCOUNT:key/<prod-key-id>
```

---

## Usage

### Minimal — attach all 10 SCPs to org root, create SOPS keys

```hcl
module "scps" {
  source = "github.com/ajay-infra/aj-tf-module-scps?ref=v0.1.0"

  management_account_id = "123456789012"
  org_root_id           = "r-ab12"
  allowed_regions       = ["us-east-1"]
}
```

### With ArgoCD decrypt grants

```hcl
module "scps" {
  source = "github.com/ajay-infra/aj-tf-module-scps?ref=v0.1.0"

  management_account_id = "123456789012"
  org_root_id           = "r-ab12"
  allowed_regions       = ["us-east-1"]

  argocd_role_arns = {
    dev     = "arn:aws:iam::111111111111:role/dev-blue-argocd-runner"
    staging = "arn:aws:iam::222222222222:role/staging-blue-argocd-runner"
    prod    = "arn:aws:iam::333333333333:role/prod-blue-argocd-runner"
  }

  engineer_role_arns = [
    "arn:aws:iam::123456789012:role/infra-lead",
    "arn:aws:iam::123456789012:role/infra-engineer",
  ]
}
```

### Scoped to specific OUs (advanced)

```hcl
module "scps" {
  source = "github.com/ajay-infra/aj-tf-module-scps?ref=v0.1.0"

  management_account_id = "123456789012"
  org_root_id           = "r-ab12"

  # Attach to specific OUs instead of root
  target_ou_ids = [
    "ou-ab12-workloads",
    "ou-ab12-security",
  ]

  # Disable a policy that conflicts with a specific workload requirement
  enabled_policies = [
    "deny-root",
    "deny-leave-org",
    "deny-disable-cloudtrail",
    # "deny-iam-users",  # disabled — legacy service requires an IAM user
    "require-imdsv2",
    "deny-unencrypted-s3",
    "restrict-regions",
    "deny-disable-guardduty",
    "deny-public-s3-acls",
    "require-ebs-encryption",
  ]
}
```

### Using envs/ file directly

```bash
terraform apply -var-file=envs/prod.tfvars
```

---

## Inputs

| Name | Required | Default | Description |
|---|---|---|---|
| `management_account_id` | yes | — | 12-digit management account ID — used in KMS key policies |
| `org_root_id` | yes | — | AWS Organizations root ID (format: `r-xxxx`) |
| `target_ou_ids` | no | `[]` | OU IDs to attach SCPs to. Empty = attach to `org_root_id` |
| `allowed_regions` | no | `["us-east-1"]` | Regions permitted by the `restrict-regions` SCP |
| `enabled_policies` | no | all 10 | List of SCP policy names to create and attach |
| `sops_environments` | no | `["dev","staging","prod"]` | Environments for which KMS SOPS keys are created |
| `argocd_role_arns` | no | `{}` | Map of `env → ArgoCD Pod Identity role ARN` for KMS Decrypt |
| `engineer_role_arns` | no | `[]` | IAM role ARNs that can Encrypt/Decrypt with SOPS locally |
| `kms_deletion_window_days` | no | `30` | KMS key deletion protection window (7–30 days) |
| `name_prefix` | no | `aj-infra` | Prefix for all resource names |
| `aws_region` | no | `us-east-1` | AWS region for KMS keys |
| `team` | no | `infra-core` | Tag |
| `cost_center` | no | `infra-2026-q1` | Tag |

---

## Outputs

### SCPs

| Output | Description |
|---|---|
| `scp_policy_ids` | Map of `policy name → Organizations policy ID` |
| `scp_policy_arns` | Map of `policy name → Organizations policy ARN` |
| `enabled_policy_names` | List of policy names that were created |

### KMS SOPS

| Output | Description |
|---|---|
| `sops_kms_key_ids` | Map of `env → KMS key ID` — reference in `.sops.yaml` |
| `sops_kms_key_arns` | Map of `env → KMS key ARN` — use in `.sops.yaml` `kms:` field |
| `sops_kms_aliases` | Map of `env → KMS alias ARN` (`alias/sops-<env>`) |

---

## Prerequisites

1. **AWS Organizations must be enabled** in the management account. SCPs require Organizations — they have no effect in a standalone account.
2. **SCP feature must be enabled** in Organizations: `aws organizations enable-policy-type --policy-type SERVICE_CONTROL_POLICY --root-id <root-id>`
3. **Terraform runs in the management account** — either directly or by assuming a role in it via GitHub OIDC.
4. **S3 state bucket and DynamoDB lock table** must exist before `terraform init`.

---

## Provider pins

| Tool | Version |
|---|---|
| Terraform | `= 1.7.5` |
| AWS provider | `= 5.100.0` |
