# Changelog

All notable changes to this module are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

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
