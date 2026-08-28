# Changelog

All notable changes to this module are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed — BREAKING
- **The 11 guardrails are now merged into 4 SCP bundles** (`baseline`, `security-hygiene`, `data-protection`, `governance`) rather than being created and attached individually. AWS caps SCP attachments at **5 per entity** (root, OU or account) and the built-in `FullAWSAccess` consumes one, leaving 4. The previous code attached every enabled policy to every target, so the documented "minimal" usage — all 11 at the org root — would have failed partway through the apply with a quota violation. This was never caught because the module has never had a consumer and has never been applied. Measured document sizes after merging: `baseline` 578, `security-hygiene` 994, `data-protection` 393, `governance` 2,125 — all well inside the 5,120-character limit.
- **`target_ou_ids` (list) replaced by `bundle_attachments` (map of bundle → targets).** Attachment is now per-bundle, so a guardrail can apply at the shallowest OU that needs it and reach the rest by inheritance. Empty map means `baseline` at `org_root_id` and nothing else.
- **Policy creation is now separate from attachment**, and the module is designed to run **once**, in a single state. The earlier plan in `aj-infra-context/arch/account-model.md` §8 — apply the module once per OU — cannot work: Organizations policy names are unique org-wide, so the second OU's apply fails with `DuplicatePolicyException`, and each run would also re-create the three SOPS KMS keys and their aliases.
- **Guardrail content is now statement objects** (`local.scp_statements`) instead of pre-encoded documents. Encoding moved to the bundle level, which is what makes merging possible. `require-tags` additionally now generates its three near-identical statements from a loop over `["Env", "Team", "ManagedBy"]` and a shared `taggable_create_actions` local, instead of repeating a 20-action list three times by hand. Encoded output is byte-identical.
- **Outputs renamed and extended**: `scp_policy_ids`/`scp_policy_arns`/`enabled_policy_names` → `scp_bundle_ids`/`scp_bundle_arns`/`bundle_members`, plus new `bundle_document_sizes` and `attachments_per_target` for quota visibility.

### Fixed
- **`require-tags` now requires `Environment`, not `Env`.** Every workload module — `aj-tf-module-vpc`, `-eks`, `-aurora`, `-valkey`, `-ecr`, `-observability` — emits `Environment` through provider `default_tags`. The guardrail demanded `Env`, a tag name that exists nowhere in the estate, so attaching the `governance` bundle to `Product/Prod/`, `Product/Regulated/` or `SaaS/Dedicated/` would have denied every `ec2:RunInstances`, `eks:CreateCluster` and `rds:CreateDBCluster` from those modules — with no account-administrator override, since that is what an SCP is. Dormant while the module had no consumer; load-bearing the moment the pipeline exists. `label-taxonomy.md` still specifies `Env`; that document describes intent rather than reality, and reconciling it is tracked separately. `governance` grows 2,125 → 2,141 chars, still far inside the 5,120 limit.

### Added
- `bundle_attachments` validates that keys are known bundle names, and that no target appears in more than 4 bundles. Note the second check cannot currently fail — with only four bundles defined, four is the maximum reachable. It guards a future fifth bundle.
- A `lifecycle` precondition on each policy asserting the document is ≤ 5,120 characters, so an oversized bundle fails at plan time rather than as a mid-apply API error.

### Fixed
- `require-tags` (11th guardrail — added in `7476fc4` after the `v0.1.0` release, but never wired into the surrounding docs/tfvars) is now included in `example.tfvars` and `envs/prod.tfvars`, matching `variables.tf`'s own default of all 11 policies. Previously silently excluded from both the CI dry-run plan and the real production tfvars — tag enforcement would not have been active if `envs/prod.tfvars` had been applied as-is.
- `README.md` / `CLAUDE.md` updated to document `require-tags` — both still said "10 guardrail policies" and omitted it from every table.
- `README.md` / `CLAUDE.md` backend-config examples updated from DynamoDB locking to S3 native locking (`use_lockfile=true`), matching the platform-wide Terraform 1.10.5 migration (`aj-infra-context/CLAUDE.md`, 2026-05-18).
- `README.md` Terraform version corrected `1.7.5` → `1.10.5` to match `providers.tf`'s actual pin.
- `skills.md` had a wrong org in its stable ref (`github.com/ajaylakma/...` → `github.com/ajay-infra/...`) and a stale branch convention (`scps-01` → the actual `v0.1.0` semver tag used everywhere else).
- `skills.md`'s "AWS tags applied" section corrected — it conflated the module's own resource tags (`Project`/`ManagedBy`/`Repository`/`Team`/`CostCenter`, from `locals.full_tags`) with the different tags `require-tags` enforces on *other* org resources (`Env`/`Team`/`ManagedBy`). There's no `env` input variable, so the module's own resources were never actually tagged `Env`.

### Removed
- Stray `.gitkeep` with actual content in it, sitting in a non-empty root directory.

### Note
- `require-tags` has not been cut into a release yet — `v0.1.0` (2026-05-17) predates it. Anyone pinning `?ref=v0.1.0` gets the original 10-policy version. Worth tagging a new release (`v0.2.0`?) once this lands, so `require-tags` is actually reachable via a stable ref.

## [v0.1.0] - 2026-05-17

Initial release — 10 SCP guardrail policies (`deny-root`, `deny-leave-org`, `deny-disable-cloudtrail`, `deny-iam-users`, `require-imdsv2`, `deny-unencrypted-s3`, `restrict-regions`, `deny-disable-guardduty`, `deny-public-s3-acls`, `require-ebs-encryption`) + per-environment SOPS KMS keys.
