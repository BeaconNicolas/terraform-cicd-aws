output "tooling_account_id" {
  description = "Account that runs the pipelines. bootstrap/target needs it."
  value       = local.account_id
}

output "state_bucket" {
  description = "Terraform state bucket. bootstrap/target and the backend migration need it."
  value       = module.state_bucket.id
}

output "source_bucket" {
  description = "Bucket that GitHub Actions uploads <env>/source.zip to."
  value       = module.source_bucket.id
}

output "kms_key_arn" {
  description = "Customer-managed key, or null when create_kms_key is false."
  value       = local.kms_key_arn
}

output "github_environment_variables" {
  description = "Variables to add to each GitHub Environment (Settings > Environments > <env>)."
  value = {
    for env, e in local.envs : env => {
      AWS_ROLE_ARN  = aws_iam_role.github[env].arn
      SOURCE_BUCKET = module.source_bucket.id
      AWS_REGION    = local.region
    }
  }
}

output "pipelines" {
  description = "Pipeline name and console link per environment."
  value = {
    for env, e in local.envs : env => {
      name = aws_codepipeline.this[env].name
      url  = "https://${local.region}.console.aws.amazon.com/codesuite/codepipeline/pipelines/${aws_codepipeline.this[env].name}/view?region=${local.region}"
    }
  }
}

output "codebuild_role_arns" {
  description = "CodeBuild role per environment. Each env's deployer role trusts only its own."
  value       = { for env, e in local.envs : env => aws_iam_role.codebuild[env].arn }
}

output "deployer_role_arns" {
  description = "Deployer role ARNs the pipelines expect bootstrap/target to create."
  value       = { for env, e in local.envs : env => e.deployer_role_arn }
}

output "target_accounts" {
  description = "Environments grouped by target account: run bootstrap/target once in each account with these environments."
  value = {
    for account in distinct([for e in values(local.envs) : e.target_account_id]) :
    account => sort([for env, e in local.envs : env if e.target_account_id == account])
  }
}
