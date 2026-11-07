# Terraform state: one bucket, one key per environment (workload/<env>.tfstate),
# locked with S3 native lock files (use_lockfile), so there is no DynamoDB table.
module "state_bucket" {
  source = "./modules/private-bucket"

  name                               = local.state_bucket_name
  force_destroy                      = var.force_destroy
  kms_key_arn                        = local.kms_key_arn
  noncurrent_version_expiration_days = 90

  # Deployer roles in other accounts may touch only their own environment's
  # state and lock file. Same-account deployers need no bucket policy entry.
  # The principal is the account root plus an aws:PrincipalArn condition, so
  # this policy can be created before the deployer roles exist.
  policy_statements = flatten([
    for env, e in local.envs : [
      {
        Sid       = "Deployer${title(env)}ListOwnState"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${e.target_account_id}:root" }
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::${local.state_bucket_name}"
        Condition = {
          StringEquals = { "aws:PrincipalArn" = e.deployer_role_arn }
          StringLike   = { "s3:prefix" = "${e.state_key}*" }
        }
      },
      {
        Sid       = "Deployer${title(env)}ReadWriteOwnState"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${e.target_account_id}:root" }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "arn:aws:s3:::${local.state_bucket_name}/${e.state_key}"
        Condition = { StringEquals = { "aws:PrincipalArn" = e.deployer_role_arn } }
      },
      {
        Sid       = "Deployer${title(env)}ManageOwnLock"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${e.target_account_id}:root" }
        Action    = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource  = "arn:aws:s3:::${local.state_bucket_name}/${e.state_key}.tflock"
        Condition = { StringEquals = { "aws:PrincipalArn" = e.deployer_role_arn } }
      },
    ] if e.cross_account
  ])
}

# Source bucket: GitHub Actions uploads <env>/source.zip here. Versioning is
# required by the CodePipeline S3 source; EventBridge notifications start the
# right pipeline without polling.
module "source_bucket" {
  source = "./modules/private-bucket"

  name                               = local.source_bucket_name
  force_destroy                      = var.force_destroy
  kms_key_arn                        = local.kms_key_arn
  noncurrent_version_expiration_days = 30
  eventbridge_notifications          = true
}

# One artifact bucket per environment keeps each pipeline's files apart.
module "artifact_bucket" {
  source   = "./modules/private-bucket"
  for_each = local.envs

  name                               = each.value.artifact_bucket_name
  force_destroy                      = var.force_destroy
  kms_key_arn                        = local.kms_key_arn
  current_version_expiration_days    = 30
  noncurrent_version_expiration_days = 1
}
