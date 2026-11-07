# Tooling (CI/CD) account: one pipeline per environment plus the shared pieces
# they need. Target accounts get their deployer roles from bootstrap/target.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region
  p          = var.project

  github_oidc_host = "token.actions.githubusercontent.com"

  state_bucket_name  = "${local.p}-tfstate-${local.account_id}-${local.region}"
  source_bucket_name = "${local.p}-cicd-source-${local.account_id}-${local.region}"

  # Everything per environment is named and derived here, so IAM policies can
  # refer to ARNs as plain strings without dependency cycles.
  envs = {
    for env, cfg in var.environments : env => {
      target_account_id = coalesce(cfg.account_id, local.account_id)
      cross_account     = coalesce(cfg.account_id, local.account_id) != local.account_id

      pipeline_name       = "${local.p}-cicd-${env}"
      pipeline_arn        = "arn:aws:codepipeline:${local.region}:${local.account_id}:${local.p}-cicd-${env}"
      github_role_name    = "${local.p}-cicd-github-${env}"
      pipeline_role_name  = "${local.p}-cicd-pipeline-${env}"
      codebuild_role_name = "${local.p}-cicd-codebuild-${env}"
      events_role_name    = "${local.p}-cicd-events-${env}"
      event_rule_name     = "${local.p}-cicd-source-${env}"
      event_rule_arn      = "arn:aws:events:${local.region}:${local.account_id}:rule/${local.p}-cicd-source-${env}"
      deployer_role_arn   = "arn:aws:iam::${coalesce(cfg.account_id, local.account_id)}:role/${local.p}-terraform-deployer-${env}"

      artifact_bucket_name = "${local.p}-cicd-artifacts-${env}-${local.account_id}-${local.region}"
      ecr_repository_name  = "${local.p}-tools-${env}"
      source_key           = "${env}/source.zip"
      state_key            = "workload/${env}.tfstate"

      codebuild_projects = {
        image = "${local.p}-cicd-image-${env}"
        test  = "${local.p}-cicd-test-${env}"
        plan  = "${local.p}-cicd-plan-${env}"
        apply = "${local.p}-cicd-apply-${env}"
      }
    }
  }

  # One entry per (environment, CodeBuild project) pair.
  codebuild_projects = merge([
    for env, e in local.envs : {
      for stage, name in e.codebuild_projects : "${env}-${stage}" => {
        env   = env
        stage = stage
        name  = name
      }
    }
  ]...)

  kms_key_arn = var.create_kms_key ? aws_kms_key.cicd[0].arn : null

  # Added to role policies only when the optional KMS key is on.
  kms_statements = var.create_kms_key ? [{
    Sid      = "UseCicdKey"
    Effect   = "Allow"
    Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
    Resource = aws_kms_key.cicd[0].arn
  }] : []
}
