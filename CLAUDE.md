# CLAUDE.md — aj-tf-module-scps

> Local context file for Claude Code. Not pushed to GitHub.

---

## What This Module Does

L0 of the platform — AWS Organizations SCPs + SOPS KMS keys. Applied once to the
management account before any cluster or workload is provisioned.

Two responsibilities:
1. **10 SCP guardrails** — org-level denies that override all IAM policies
2. **KMS SOPS keys** — one per env (dev/staging/prod), used by ksops in ArgoCD

---

## Module Structure

```
locals.tf    → all SCP policy content (jsonencode inline) + computed cross-products
main.tf      → aws_organizations_policy, attachment, aws_kms_key, aws_kms_alias
variables.tf → inputs: management_account_id, org_root_id, target_ou_ids,
               enabled_policies, allowed_regions, sops_environments,
               argocd_role_arns, engineer_role_arns
outputs.tf   → scp_policy_ids/arns, sops_kms_key_ids/arns/aliases
providers.tf → AWS provider with skip_* flags for CI dry run
```

No submodules — SCPs are flat (policy + attachment), KMS keys are for_each.

---

## Key Design Decisions

- **All policy content inline via jsonencode** — no separate JSON files, no templatefile
  needed. The regions list in restrict-regions stays a variable. Easier to review.
- **enabled_policies list** — defaults to all 10. Remove a name to skip that SCP.
- **management_account_id variable** — no data.aws_caller_identity, so CI plan dry
  run works with dummy creds + skip_* flags.
- **argocd_role_arns defaults to {}** — add once ArgoCD is deployed and Pod Identity
  roles are known. KMS key policy skips the ArgoCD statement when empty.
- **target_ou_ids defaults to []** — empty = attach to org_root_id. Scope to specific
  OUs as the org matures.

---

## CI Dry Run

Plan dry run works because:
- providers.tf has skip_credentials_validation/skip_requesting_account_id = true
- No data sources that call AWS (management_account_id is a variable)
- aws_organizations_policy + aws_kms_key are resources — plan just computes them

---

## Applying to Production

```bash
# Run in the management account (or assume role into it)
terraform init \
  -backend-config="bucket=tf-state-central-MGMT_ACCOUNT" \
  -backend-config="key=org/scps/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="dynamodb_table=tf-locks-central"

terraform apply -var-file=envs/prod.tfvars
```

After apply:
1. Copy `sops_kms_key_arns` output into k8s-manifests/.sops.yaml
2. Engineers run `sops -e` to encrypt secrets using their role in engineer_role_arns
3. ArgoCD decrypts at render time via ksops + argocd_role_arns

---

## Known TODOs

- [ ] Wire argocd_role_arns once ArgoCD is deployed (aj-infra-central)
- [ ] Add engineer_role_arns once IAM Identity Center is configured
- [ ] Scope target_ou_ids to specific OUs once org structure is defined
- [ ] provision-org.yml pipeline in aj-infra-release
