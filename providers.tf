terraform {
  required_version = "= 1.7.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
  }

  # Backend configured dynamically by pipelines via -backend-config
  # backend "s3" {
  #   bucket         = "<tf-state-bucket>"
  #   key            = "org/scps/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "tf-locks-central"
  #   role_arn       = "arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/GitHubActions-Terraform"
  # }
}

# Must be run in the management account — SCPs and KMS keys are management-plane resources.
# In CI dry run: skip_credentials_validation skips the STS call; plan works with dummy creds.
provider "aws" {
  region = var.aws_region

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  default_tags {
    tags = local.full_tags
  }
}
