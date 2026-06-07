# skills.md — aj-tf-module-scps

## Purpose
Provisions AWS Service Control Policies (SCPs) at the Organization level. Enforces region restrictions, required tagging, and guardrails across all member accounts.

## Type
`tf-module`

## Stable ref
```
source = "github.com/ajaylakma/aj-tf-module-scps?ref=scps-01"
```

## Key inputs
| Variable | Description |
|---|---|
| `management_account_id` | AWS Org management account ID |
| `org_root_id` | Org root ID for policy attachment |
| `target_ou_ids` | OUs to attach policies to |
| `enabled_policies` | List of policy names to enable |
| `allowed_regions` | Regions where resource creation is permitted |
| `sops_environments` | Environments where SOPS encryption is enforced |

## Enforced guardrails (label-taxonomy alignment)
11 policies total. The `require-tags` policy denies resource creation unless these tags are present:
- `Env` — environment (dev | staging | uat | prod)
- `Team` — owning team slug
- `ManagedBy` — terraform | manual

Covered services: EC2, VPC subnets/SGs/IGW/NAT/volumes, Client VPN, EKS cluster+nodegroup,
RDS cluster+instance, ElastiCache, KMS, CloudFront, ELB, ECR, CloudWatch Logs, Directory Service.
Service-linked roles are excluded (EKS/RDS/ElastiCache internal operations).

## AWS tags applied
`Env`, `Team`, `ManagedBy` (on the SCP resources themselves)

## Branching convention
- `main` — active development
- `scps-01` — stable pinned release

## CI checks
fmt, validate, plan (dry-run), tfsec/checkov

## Agentic capabilities
- Audit member accounts for SCP coverage gaps
- Detect resources missing required tags (`Env`, `Team`, `ManagedBy`)
- Generate PR to add new guardrail policy
- Validate allowed_regions matches platform region strategy
- Weekly scan: flag any manually created resources bypassing Terraform
