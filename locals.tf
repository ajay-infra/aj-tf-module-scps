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
    # is missing. This is by far the largest guardrail (~2,125 chars encoded,
    # because the action list repeats three times) which is why it sits alone
    # in its own bundle.
    require-tags = [
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
      "require-tags",
    ]
  }

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
  resolved_attachments = length(var.bundle_attachments) > 0 ? var.bundle_attachments : {
    baseline = [var.org_root_id]
  }

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
    env => "SOPS encryption key — ${env} environment secrets in k8s-manifests"
  }
}
