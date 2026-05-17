locals {
  # Attach to root OU if no specific OUs provided
  attachment_targets = length(var.target_ou_ids) > 0 ? var.target_ou_ids : [var.org_root_id]

  full_tags = merge({
    Project    = "aj-infra-platform"
    ManagedBy  = "Terraform"
    Repository = "aj-tf-module-scps"
    Team       = var.team
    CostCenter = var.cost_center
  }, var.tags)

  # ── SCP Policy Content ──────────────────────────────────────────────────────
  # All 10 guardrail policies. Only policies in var.enabled_policies are created.
  # Use jsonencode so the regions list in restrict-regions stays a variable.

  scp_policy_content = {

    # Root user — no actions allowed except break-glass account recovery.
    # The condition targets the root ARN pattern across all accounts.
    deny-root = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # Prevent member accounts from detaching themselves from the org.
    deny-leave-org = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "DenyLeaveOrg"
        Effect   = "Deny"
        Action   = "organizations:LeaveOrganization"
        Resource = "*"
      }]
    })

    # CloudTrail must always be on. Disabling or deleting it is blocked.
    # UpdateTrail is included to prevent disabling logging via update.
    deny-disable-cloudtrail = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # No IAM users — all human access via IAM Identity Center (SSO).
    # Machine access via IAM roles only. This forces a zero-standing-privilege posture.
    deny-iam-users = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid    = "DenyIAMUsers"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:UpdateAccessKey",
        ]
        Resource = "*"
      }]
    })

    # IMDSv2 required on all EC2 instances (including EKS nodes).
    # IMDSv1 is exploitable via SSRF — blocking it at org level means no exceptions.
    require-imdsv2 = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # All S3 writes must use server-side encryption.
    # Covers both KMS and AES256 — no unencrypted objects ever.
    deny-unencrypted-s3 = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # Restrict all API calls to allowed_regions.
    # NotAction excludes global/IAM-plane services that are region-agnostic.
    restrict-regions = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # GuardDuty must stay on. Deleting detectors or disassociating from
    # the org master account are both blocked.
    deny-disable-guardduty = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # Belt-and-suspenders alongside S3 Block Public Access.
    # Prevents setting public-read or public-read-write ACLs on any bucket or object.
    deny-public-s3-acls = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })

    # All EBS volumes must be encrypted. Blocks RunInstances if any attached
    # volume does not have encryption enabled.
    require-ebs-encryption = jsonencode({
      Version = "2012-10-17"
      Statement = [{
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
    })
  }

  # Only the policies in var.enabled_policies are created
  active_policies = {
    for name, content in local.scp_policy_content :
    name => content
    if contains(var.enabled_policies, name)
  }

  # Cross-product of active policies × attachment targets
  # Each pair becomes one aws_organizations_policy_attachment resource
  policy_target_pairs = {
    for pair in setproduct(keys(local.active_policies), local.attachment_targets) :
    "${pair[0]}--${pair[1]}" => {
      policy_name = pair[0]
      target_id   = pair[1]
    }
  }

  # KMS SOPS key descriptions
  sops_key_descriptions = {
    for env in var.sops_environments :
    env => "SOPS encryption key — ${env} environment secrets in k8s-manifests"
  }
}
