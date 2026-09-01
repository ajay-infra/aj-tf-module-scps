locals {
  full_tags = merge({
    Project    = "aj-infra-platform"
    ManagedBy  = "Terraform"
    Repository = "aj-tf-module-scps"
    Team       = var.team
    CostCenter = var.cost_center
  }, var.tags)

  # Actions that support aws:RequestTag at creation time. Anything not on this
  # list cannot be tag-gated by an SCP — the condition key simply is not present
  # in the request, so a Null check on it would deny unconditionally.
  taggable_create_actions = [
    "ec2:RunInstances",
    "ec2:CreateVpc",
    "ec2:CreateSubnet",
    "ec2:CreateSecurityGroup",
    "ec2:CreateInternetGateway",
    "ec2:CreateNatGateway",
    "ec2:CreateVolume",
    "ec2:CreateClientVpnEndpoint",
    "eks:CreateCluster",
    "eks:CreateNodegroup",
    "rds:CreateDBCluster",
    "rds:CreateDBInstance",
    "elasticache:CreateReplicationGroup",
    "elasticache:CreateServerlessCache",
    "kms:CreateKey",
    "cloudfront:CreateDistribution",
    "elasticloadbalancing:CreateLoadBalancer",
    "ecr:CreateRepository",
    "logs:CreateLogGroup",
    "ds:CreateDirectory",
  ]

  # Service-linked roles are excluded from every tag guardrail — EKS/RDS/
  # ElastiCache create resources through them internally and propagate tags
  # separately, via tag propagation on the parent resource.
  service_linked_role_exemption = {
    "aws:PrincipalArn" = "arn:aws:iam::*:role/aws-service-role/*"
  }

  # ── Guardrail statements ────────────────────────────────────────────────────
  # These are statement OBJECTS, not encoded policy documents. Encoding happens
  # per-bundle below.
  #
  # Why bundles exist: AWS Organizations caps SCP *attachments* at 5 per entity
  # (root, OU or account), and the always-present FullAWSAccess consumes one of
  # those — so the real budget is 4 custom SCPs per entity. That quota is hard;
  # it cannot be raised through Service Quotas. A single SCP *document*, on the
  # other hand, may be up to 5,120 characters. Merging related guardrails into
  # one document therefore trades cheap document space for scarce attachment
  # slots. Attaching these 11 guardrails individually would need 11 slots and
  # fail on the fifth.

  scp_statements = {

    # Root user — no actions allowed except break-glass account recovery.
    # The condition targets the root ARN pattern across all accounts.
    deny-root = [{
      Sid      = "DenyRootUser"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = "arn:aws:iam::*:root"
        }
      }
    }]

    # Prevent member accounts from detaching themselves from the org.
    deny-leave-org = [{
      Sid      = "DenyLeaveOrg"
      Effect   = "Deny"
      Action   = "organizations:LeaveOrganization"
      Resource = "*"
    }]

    # CloudTrail must always be on. Disabling or deleting it is blocked.
    # UpdateTrail is included to prevent disabling logging via update.
    deny-disable-cloudtrail = [{
      Sid    = "DenyDisableCloudTrail"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail",
        "cloudtrail:PutEventSelectors",
      ]
      Resource = "*"
    }]

    # No IAM users — all human access via IAM Identity Center (SSO).
    # Machine access via IAM roles only. This forces a zero-standing-privilege posture.
    deny-iam-users = [{
      Sid    = "DenyIAMUsers"
      Effect = "Deny"
      Action = [
        "iam:CreateUser",
        "iam:CreateAccessKey",
        "iam:UpdateAccessKey",
      ]
      Resource = "*"
    }]

    # IMDSv2 required on all EC2 instances (including EKS nodes).
    # IMDSv1 is exploitable via SSRF — blocking it at org level means no exceptions.
    require-imdsv2 = [{
      Sid      = "RequireIMDSv2"
      Effect   = "Deny"
      Action   = "ec2:RunInstances"
      Resource = "arn:aws:ec2:*:*:instance/*"
      Condition = {
        StringNotEquals = {
          "ec2:MetadataHttpTokens" = "required"
        }
      }
    }]

    # All S3 writes must use server-side encryption.
    # Covers both KMS and AES256 — no unencrypted objects ever.
    deny-unencrypted-s3 = [{
      Sid      = "DenyUnencryptedS3"
      Effect   = "Deny"
      Action   = "s3:PutObject"
      Resource = "*"
      Condition = {
        Null = {
          "s3:x-amz-server-side-encryption" = "true"
        }
      }
    }]

    # Restrict all API calls to allowed_regions.
    # NotAction excludes global/IAM-plane services that are region-agnostic.
    restrict-regions = [{
      Sid    = "RestrictRegions"
      Effect = "Deny"
      NotAction = [
        "a4b:*",
        "acm:*",
        "aws-portal:*",
        "budgets:*",
        "ce:*",
        "cloudfront:*",
        "cur:*",
        "globalaccelerator:*",
        "health:*",
        "iam:*",
        "importexport:*",
        "organizations:*",
        "pricing:*",
        "route53:*",
        "sts:*",
        "support:*",
        "trustedadvisor:*",
        "waf:*",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = var.allowed_regions
        }
      }
    }]

    # GuardDuty must stay on. Deleting detectors or disassociating from
    # the org master account are both blocked.
    deny-disable-guardduty = [{
      Sid    = "DenyDisableGuardDuty"
      Effect = "Deny"
      Action = [
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromAdministratorAccount",
        "guardduty:DisassociateFromMasterAccount",
        "guardduty:DisassociateMembers",
        "guardduty:StopMonitoringMembers",
      ]
      Resource = "*"
    }]

    # Belt-and-suspenders alongside S3 Block Public Access.
    # Prevents setting public-read or public-read-write ACLs on any bucket or object.
    deny-public-s3-acls = [{
      Sid    = "DenyPublicS3ACLs"
      Effect = "Deny"
      Action = [
        "s3:PutBucketAcl",
        "s3:PutObjectAcl",
      ]
      Resource = "*"
      Condition = {
        StringEquals = {
          "s3:x-amz-acl" = [
            "public-read",
            "public-read-write",
            "authenticated-read",
          ]
        }
      }
    }]

    # All EBS volumes must be encrypted. Blocks RunInstances if any attached
    # volume does not have encryption enabled.
    require-ebs-encryption = [{
      Sid      = "RequireEBSEncryption"
      Effect   = "Deny"
      Action   = "ec2:RunInstances"
      Resource = "arn:aws:ec2:*:*:volume/*"
      Condition = {
        Bool = {
          "ec2:Encrypted" = "false"
        }
      }
    }]

    # ── PRODUCT PROFILE ONLY ────────────────────────────────────────────────
    # This guardrail encodes the PRODUCT tagging profile. SaaS is a separate
    # stack with a different profile that is not yet defined — see
    # aj-infra-context/arch/tag-profiles.md.
    #
    # The `governance` bundle carrying this must therefore attach to PRODUCT
    # OUs only. Attaching it to SaaS/ would force product's schema onto a stack
    # that does not use it: satisfiable with values that mean nothing there, so
    # the tags look complete while the cost data is meaningless. A SaaS bundle
    # attaches separately once its profile exists — the per-bundle attachment
    # model already supports that at no architectural cost.
    #
    # Four required tags on every Terraform-managed resource:
    #   Environment — environment (dev | staging | prod | prod-regulated | …)
    #   Team        — owning team slug
    #   ManagedBy   — terraform | manual
    #   CostCenter  — chargeback code
    #
    # CostCenter added 2026-08-28. Every module already emitted it via
    # local.full_tags and nothing required it — so the tag most directly used
    # for chargeback was the one that could go missing silently. Of the other
    # three, only Environment and Team carry cost meaning; ManagedBy is
    # governance.
    #
    # NOT added, deliberately: Class and Customer. They are defined in
    # label-taxonomy.md and NO MODULE EMITS THEM YET. Requiring a tag before the
    # emit side exists is exactly the failure this policy already had once,
    # when it demanded `Env` and every module produced `Environment` — it would
    # deny every RunInstances, CreateCluster and CreateDBCluster in the OU with
    # no administrator override. Modules first, SCP second.
    #
    # NOTE the tag is Environment, not Env. Every workload module
    # (aj-tf-module-vpc, -eks, -aurora, -valkey, -ecr, -observability) emits
    # `Environment` via provider default_tags. Requiring `Env` here would deny
    # every one of their creates in any OU this bundle attaches to, and no
    # account administrator could override it. label-taxonomy.md still says
    # `Env`; that document describes intent, not reality, and reconciling it is
    # tracked separately.
    #
    # One Deny statement per tag so the violation message identifies which tag
    # is missing. This is by far the largest guardrail — 2,846 chars encoded at
    # four tags, because the action list repeats in every statement — which is
    # why it sits alone in its own bundle.
    #
    # Roughly 710 chars per tag. That number is the budget: see governance-saas.
    require-tags-product = [
      for tag in ["Environment", "Team", "ManagedBy", "CostCenter"] : {
        Sid      = "RequireTag${tag}"
        Effect   = "Deny"
        Action   = local.taggable_create_actions
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/${tag}" = "true"
          }
          StringNotLike = local.service_linked_role_exemption
        }
      }
    ]

    # ── SaaS tagging profile ──────────────────────────────────────────────────
    # The SAME four tags as require-tags-product, plus Customer and ProductLine.
    #
    # SaaS has two independent chargeback axes where product has one. Revenue is
    # contracted per customer and recognised per product line; a customer buys
    # several lines, and a line is sold to many customers. Neither fact derives
    # from the other, so they cannot share a key.
    #
    # Team is required here too but is NOT narrowed to a product code — that
    # narrowing is product-only and lives in the require-product-code Gatekeeper
    # constraint, not here.
    #
    # PRESENCE ONLY, never vocabulary. This checks that ProductLine exists; it
    # does not check the value is a real line. A closed list of product lines in
    # an SCP would mean editing the one control an account administrator cannot
    # override every time the business names a product — org-wide blast radius
    # for a routine event. The vocabulary lives in the allowedLines parameter of
    # aj-cluster-baseline/policies/constraints/require-product-line.yaml.
    #
    # ⚠ THIS GUARDRAIL MUST NOT BE ATTACHED YET. No module emits Customer or
    # ProductLine. Attaching it would deny every RunInstances, CreateCluster and
    # CreateDBCluster in the SaaS OUs with no administrator override — precisely
    # the `Env` failure recorded above, with two tags instead of one. Enabling it
    # without attaching creates the policy document and proves it renders under
    # the 5,120-char limit at plan time, which costs nothing and is the only
    # signal available in a dry-run estate.
    #
    # Order: modules emit -> a SaaS account is observed carrying them -> attach.
    # See aj-infra-context/arch/tag-profiles.md §5.6.
    #
    # Sids repeat those in require-tags-product. Harmless — Sid must be unique
    # within a DOCUMENT, and these two guardrails are in different bundles by
    # construction. Do not put them in the same bundle.
    require-tags-saas = [
      for tag in ["Environment", "Team", "ManagedBy", "CostCenter", "Customer", "ProductLine"] : {
        Sid      = "RequireTag${tag}"
        Effect   = "Deny"
        Action   = local.taggable_create_actions
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/${tag}" = "true"
          }
          StringNotLike = local.service_linked_role_exemption
        }
      }
    ]
  }

  # ── Bundles ─────────────────────────────────────────────────────────────────
  # Grouped by the shallowest OU the guardrail should apply to, so that SCP
  # inheritance does the distribution. See README "Bundles and attachment".

  scp_bundles = {
    # Universal. Nothing in the org is exempt — attach at root.
    baseline = [
      "deny-root",
      "deny-leave-org",
      "deny-disable-cloudtrail",
      "deny-iam-users",
    ]

    # Compute and blast-radius hygiene. Everything except Sandbox.
    security-hygiene = [
      "require-imdsv2",
      "require-ebs-encryption",
      "deny-disable-guardduty",
      "restrict-regions",
    ]

    # Data exposure. Everything holding real data — not Sandbox.
    data-protection = [
      "deny-unencrypted-s3",
      "deny-public-s3-acls",
    ]

    # Chargeback and ownership enforcement. Production-grade OUs only:
    # requiring tags in dev/sandbox blocks console experimentation for no
    # benefit, since those accounts are not charged back.
    governance = [
      "require-tags-product",
    ]

    # The SaaS tagging profile. A SEPARATE bundle rather than more statements in
    # `governance`, because the two profiles attach to different OUs — that is
    # the whole point of profiles, and the per-bundle attachment model built for
    # the 5-attachments-per-entity quota already supports it at no cost.
    #
    # Six tags, 4,254 chars encoded against a 5,120-char document limit —
    # verified by plan, not estimated. Each tag costs ~710 chars because the
    # action list repeats in every Deny statement.
    #
    # SO THERE IS ROOM FOR EXACTLY ONE MORE REQUIRED TAG. A seventh lands at
    # ~4,965; an eighth exceeds the limit and the precondition in main.tf fails
    # the plan. If SaaS ever needs an eighth, the fix is to split this into two
    # bundles — which costs an attachment slot on SaaS/, taking it from 3 to 4
    # against a ceiling of 4. Worth knowing before that day, not on it.
    #
    # ⚠ Currently attached to NOTHING. See require-tags-saas above for why, and
    # for the order in which that changes.
    #
    # When it is attached, it goes to SaaS/ rather than only the production-grade
    # OUs the way `governance` does. That divergence is deliberate: product skips
    # tag enforcement in dev and sandbox because those accounts are not charged
    # back, but a pooled SaaS cluster is multi-customer at EVERY stage, and
    # unattributed pooled spend is the exact gap these tags exist to close.
    # Attachments landing on SaaS/ would then be 3, against a ceiling of 4.
    governance-saas = [
      "require-tags-saas",
    ]
  }

  # Names in enabled_policies that match no guardrail. This exists because
  # renaming a guardrail silently DELETES a bundle: bundle_members filters by
  # contains(var.enabled_policies, name), so a stale name matches nothing, the
  # bundle empties, active_bundles drops it, and bundle_target_pairs skips its
  # attachments.
  #
  # Nothing errors. The guardrail simply is not there.
  #
  # That happened on 2026-08-29 renaming require-tags -> require-tags-product:
  # the module was updated, a consumer's enabled_policies was not, and the
  # governance bundle attached to ZERO OUs while every plan stayed green.
  unknown_enabled_policies = [
    for name in var.enabled_policies : name
    if !contains(keys(local.scp_statements), name)
  ]

  # var.enabled_policies gates individual guardrails; a bundle whose members are
  # all disabled is not created at all.
  bundle_members = {
    for bundle, names in local.scp_bundles :
    bundle => [for name in names : name if contains(var.enabled_policies, name)]
  }

  active_bundles = {
    for bundle, names in local.bundle_members :
    bundle => jsonencode({
      Version   = "2012-10-17"
      Statement = flatten([for name in names : local.scp_statements[name]])
    })
    if length(names) > 0
  }

  # ── Attachment ──────────────────────────────────────────────────────────────
  # Empty bundle_attachments means "minimum viable guardrail": the universal
  # bundle at the org root, one attachment, nothing else. Real deployments pass
  # the full OU map — see envs/prod.tfvars.
  # The three attachment maps merge into one. A bundle named in more than one
  # gets the union of its targets, so product and saas can each attach the same
  # bundle to their own OU without knowing about each other.
  merged_attachments = {
    for bundle in distinct(concat(
      keys(var.bundle_attachments),
      keys(var.product_bundle_attachments),
      keys(var.saas_bundle_attachments),
      )) : bundle => distinct(concat(
      lookup(var.bundle_attachments, bundle, []),
      lookup(var.product_bundle_attachments, bundle, []),
      lookup(var.saas_bundle_attachments, bundle, []),
    ))
  }

  # Empty means "minimum viable guardrail": the universal bundle at the org
  # root, one attachment, nothing else.
  resolved_attachments = length(local.merged_attachments) > 0 ? local.merged_attachments : {
    baseline = [var.org_root_id]
  }

  # The 5-per-entity quota applies to the MERGED map, and no variable validation
  # block can see more than its own variable. Splitting the map without moving
  # this check is how a target ends up in three bundles from one file and two
  # from another, passing both validations and failing at the fifth attachment
  # against live AWS.
  over_cap_targets = [
    for target in distinct(flatten(values(local.resolved_attachments))) : target
    if length([for b, ts in local.resolved_attachments : b if contains(ts, target)]) > 4
  ]

  # One aws_organizations_policy_attachment per (bundle, target) pair, skipping
  # any bundle that was not created because all its members are disabled.
  bundle_target_pairs = {
    for pair in flatten([
      for bundle, targets in local.resolved_attachments : [
        for target in targets : {
          bundle    = bundle
          target_id = target
        }
      ] if contains(keys(local.active_bundles), bundle)
    ]) : "${pair.bundle}--${pair.target_id}" => pair
  }

  # KMS SOPS key descriptions
  sops_key_descriptions = {
    for env in var.sops_environments :
    env => "SOPS encryption key — ${env} environment secrets in aj-cluster-baseline"
  }
}
