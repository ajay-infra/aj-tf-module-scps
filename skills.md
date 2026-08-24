# skills.md — aj-tf-module-scps

## Purpose
Provisions AWS Service Control Policies (SCPs) at the Organization level. Enforces region restrictions, required tagging, and guardrails across all member accounts.

## Type
`tf-module`

## Stable ref
```
source = "github.com/ajay-infra/aj-tf-module-scps?ref=v0.1.0"
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
On the SCP module's own resources: `Project`, `ManagedBy`, `Repository`, `Team`, `CostCenter` (see `locals.full_tags`). This is separate from `Env`/`Team`/`ManagedBy` — the tags the `require-tags` *policy* enforces on other org resources (EC2, EKS, RDS, etc.); there's no `env` input variable, so the module's own resources are never tagged `Env`.

## Branching convention
- `main` — active development
- semver tags (`v0.1.0`, ...) — stable pinned releases, per `README.md` usage examples

## CI checks
fmt, validate, plan (dry-run), tfsec/checkov

## Agentic capabilities
- Audit member accounts for SCP coverage gaps
- Detect resources missing required tags (`Env`, `Team`, `ManagedBy`)
- Generate PR to add new guardrail policy
- Validate allowed_regions matches platform region strategy
- Weekly scan: flag any manually created resources bypassing Terraform
