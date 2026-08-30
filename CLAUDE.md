# CLAUDE.md — aj-tf-module-scps

> Local context file for Claude Code. Not pushed to GitHub.

---

## What This Module Does

L0 of the platform — AWS Organizations SCPs + SOPS KMS keys. Applied once to the
management account before any cluster or workload is provisioned.

Two responsibilities:
1. **12 SCP guardrails**, merged into **5 bundles**, 4 of them attached —
   org-level denies that override all IAM policies
2. **KMS SOPS keys** — one per env (dev/staging/prod), used by ksops in ArgoCD

---

## Module Structure

```
locals.tf    → guardrail STATEMENTS (objects, not encoded docs), bundle
               definitions, per-bundle encoding, attachment pairs
main.tf      → aws_organizations_policy (per bundle), attachment (per pair),
               aws_kms_key, aws_kms_alias
variables.tf → inputs: management_account_id, org_root_id, bundle_attachments,
               enabled_policies, allowed_regions, sops_environments,
               argocd_role_arns, engineer_role_arns
outputs.tf   → scp_bundle_ids/arns, bundle_members, bundle_document_sizes,
               attachments_per_target, sops_kms_key_ids/arns/aliases
providers.tf → AWS provider with skip_* flags for CI dry run
```

No submodules — SCPs are flat (policy + attachment), KMS keys are for_each.

---

## Key Design Decisions

- **Guardrails are statement objects, encoded per bundle** — `scp_statements` holds
  raw statement lists so they can be merged; `jsonencode` happens once per bundle.
  Previously each guardrail was pre-encoded, which made merging impossible.
- **12 guardrails → 5 bundles.** AWS caps SCP attachments at **5 per entity** and
  FullAWSAccess takes one, leaving 4. A document can be 5,120 chars. So merging
  trades cheap space for a scarce, unraisable quota. Attaching them individually
  fails on the fifth — the reason the pre-bundle module could never have applied.
- **Creation is separate from attachment.** Policy names are unique org-wide, so
  the module runs ONCE, in one state, and attaches to many OUs. Running it per-OU
  (the original plan in account-model.md §8) hits DuplicatePolicyException on the
  second apply and duplicates the SOPS KMS keys.
- **Attachment depth is free, breadth is not.** The 5-per-entity quota counts
  direct attachments only; inherited SCPs are evaluated but consume no slots.
- **enabled_policies list** — defaults to all 12. Remove a name to drop it from
  whichever bundle holds it. Emptying a bundle means it is not created.
- **management_account_id variable** — no data.aws_caller_identity, so CI plan dry
  run works with dummy creds + skip_* flags.
- **argocd_role_arns defaults to {}** — add once ArgoCD is deployed and Pod Identity
  roles are known. KMS key policy skips the ArgoCD statement when empty.
- **bundle_attachments defaults to {}** — empty = `baseline` at org_root_id only.
  Safe, because an unattached SCP has no effect. Real deployments pass the full map.

---

## CI Dry Run

Plan dry run works because:
- providers.tf has skip_credentials_validation/skip_requesting_account_id = true
- No data sources that call AWS (management_account_id is a variable)
- aws_organizations_policy + aws_kms_key are resources — plan just computes them

Verified 2026-08-29: `terraform plan` against `example.tfvars` yields 20 resources
(**5** policies, 10 attachments, 3 KMS keys, 3 aliases) with dummy credentials.
Measured bundle sizes: baseline 578, data-protection 393, security-hygiene 994,
governance 2,846, governance-saas 4,254 — all under the 5,120 limit.
`governance-saas` is created and attached to nothing, on purpose.

---

## Applying to Production

```bash
# Run in the management account (or assume role into it)
terraform init \
  -backend-config="bucket=tf-state-central-MGMT_ACCOUNT" \
  -backend-config="key=org/scps/terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true"

terraform apply -var-file=envs/prod.tfvars
```

After apply:
1. Copy `sops_kms_key_arns` output into aj-cluster-baseline/.sops.yaml
2. Engineers run `sops -e` to encrypt secrets using their role in engineer_role_arns
3. ArgoCD decrypts at render time via ksops + argocd_role_arns

---

## Known TODOs

- [ ] **Do not attach `governance-saas` until modules emit `Customer` and
      `ProductLine`.** It requires two tags nothing produces; attaching it would
      deny every create in the SaaS OUs. Same defect this policy had with `Env`.
      See aj-infra-context/arch/tag-profiles.md §5.6 for the order.

- [ ] Wire argocd_role_arns once ArgoCD is deployed (aj-infra-central)
- [ ] Add engineer_role_arns once IAM Identity Center is configured
- [ ] Replace REPLACE_WITH_* placeholders in envs/prod.tfvars once the org exists
- [x] provision-org.yml pipeline in aj-infra-release (2026-08-27)
- [ ] **Tag v0.2.0.** aj-infra-release/versions.yaml already pins
      `org.scps_module_tag: v0.2.0`, but only v0.1.0 exists. v0.1.0 predates
      bundling and rejects `bundle_attachments` — the pipeline fails until tagged.
