# Offline tests for the tooling stack. The AWS provider is mocked, so these
# "apply" runs make no AWS calls; they check what Terraform would create.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  # Some arguments must look like real ARNs, so give the mocks realistic ones.
  mock_resource "aws_sns_topic" {
    defaults = { arn = "arn:aws:sns:eu-west-1:111111111111:mock-topic" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock-role" }
  }
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:eu-west-1:111111111111:key/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_codepipeline" {
    defaults = { arn = "arn:aws:codepipeline:eu-west-1:111111111111:mock-pipeline" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::mock-bucket" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:eu-west-1:111111111111:repository/mock"
      repository_url = "111111111111.dkr.ecr.eu-west-1.amazonaws.com/mock"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-1:111111111111:log-group:mock" }
  }
  mock_resource "aws_codebuild_project" {
    defaults = { arn = "arn:aws:codebuild:eu-west-1:111111111111:project/mock" }
  }
}

variables {
  project            = "demo"
  aws_region         = "eu-west-1"
  github_owner       = "example-owner"
  github_repo        = "example-repo"
  notification_email = "alerts@example.com"
}

run "single_account_defaults" {
  assert {
    condition     = length(aws_codepipeline.this) == 3 && length(aws_codebuild_project.stage) == 12
    error_message = "Expected one pipeline and four CodeBuild projects for each of dev, int and prod."
  }

  assert {
    condition     = [for s in aws_codepipeline.this["dev"].stage : s.name] == ["Source", "ToolsImage", "Test", "Plan", "Approve", "Apply"]
    error_message = "Pipeline stages are out of order."
  }

  assert {
    condition     = aws_codepipeline.this["dev"].pipeline_type == "V2" && aws_codepipeline.this["dev"].name == "demo-cicd-dev"
    error_message = "Pipeline must be V2 and named <project>-cicd-<env>."
  }

  assert {
    condition     = aws_codepipeline.this["prod"].stage[0].action[0].configuration.PollForSourceChanges == "false"
    error_message = "The S3 source must not poll; EventBridge starts the pipeline."
  }

  assert {
    condition     = aws_codepipeline.this["prod"].stage[0].action[0].configuration.S3ObjectKey == "prod/source.zip"
    error_message = "Each pipeline must read only its own <env>/source.zip."
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.source["int"].event_pattern).detail.object.key == ["int/source.zip"] && jsondecode(
    aws_cloudwatch_event_rule.source["int"].event_pattern)["detail-type"] == ["Object Created"]
    error_message = "The int rule must match only Object Created events for int/source.zip."
  }

  assert {
    condition     = length(aws_kms_key.cicd) == 0 && aws_ecr_repository.tools["dev"].encryption_configuration[0].encryption_type == "AES256"
    error_message = "No customer-managed KMS key by default (it is billed while idle)."
  }

  assert {
    condition     = length(jsondecode(module.state_bucket.policy).Statement) == 1
    error_message = "Single account: the state bucket policy only denies plain HTTP; IAM policies grant access."
  }

  assert {
    condition     = aws_ecr_repository.tools["dev"].image_tag_mutability == "IMMUTABLE_WITH_EXCLUSION" && aws_ecr_repository.tools["dev"].image_scanning_configuration[0].scan_on_push
    error_message = "ECR tags must be immutable (except 'current') and images scanned on push."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly) == 1
    error_message = "The budget must be created by default."
  }
}

run "roles_trust_only_what_they_should" {
  assert {
    condition = jsondecode(aws_iam_role.github["dev"].assume_role_policy).Statement[0].Condition.StringEquals == {
      "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
      "token.actions.githubusercontent.com:sub" = "repo:example-owner/example-repo:environment:dev"
    }
    error_message = "The dev GitHub role must trust only the dev environment of this repository."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.github["dev"].policy).Statement[0].Action == "s3:PutObject" && endswith(jsondecode(aws_iam_role_policy.github["dev"].policy).Statement[0].Resource, "/dev/source.zip")
    error_message = "The dev GitHub role may only put dev/source.zip."
  }

  assert {
    condition = jsondecode(aws_iam_role.pipeline["dev"].assume_role_policy).Statement[0].Condition.StringEquals == {
      "aws:SourceAccount" = "111111111111"
      "aws:SourceArn"     = "arn:aws:codepipeline:eu-west-1:111111111111:demo-cicd-dev"
    }
    error_message = "The pipeline role must carry confused-deputy conditions for its own pipeline."
  }

  assert {
    condition     = length(jsondecode(aws_iam_role.codebuild["int"].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceArn"]) == 4
    error_message = "The CodeBuild role must trust only its own environment's four projects."
  }

  assert {
    condition     = jsondecode(aws_iam_role.events["prod"].assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceArn"] == "arn:aws:events:eu-west-1:111111111111:rule/demo-cicd-source-prod"
    error_message = "The events role must trust only its own rule."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.events["prod"].policy).Statement[0].Resource == "arn:aws:codepipeline:eu-west-1:111111111111:demo-cicd-prod"
    error_message = "The events role may only start its own pipeline."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.codebuild["dev"].policy).Statement : s.Resource if s.Action == "sts:AssumeRole"
    ]) == "arn:aws:iam::111111111111:role/demo-terraform-deployer-dev"
    error_message = "The dev CodeBuild role may assume only the dev deployer role."
  }
}

run "codebuild_projects" {
  assert {
    condition     = aws_codebuild_project.stage["dev-image"].environment[0].privileged_mode && aws_codebuild_project.stage["dev-image"].environment[0].compute_type == "BUILD_GENERAL1_SMALL"
    error_message = "The image project needs Docker (privileged) on the free-tier size."
  }

  assert {
    condition = alltrue([
      for k in ["dev-test", "dev-plan", "dev-apply"] :
      !aws_codebuild_project.stage[k].environment[0].privileged_mode
      && aws_codebuild_project.stage[k].environment[0].image_pull_credentials_type == "SERVICE_ROLE"
      && endswith(aws_codebuild_project.stage[k].environment[0].image, ":current")
    ])
    error_message = "Test, Plan and Apply must run the tools image, pulled with the service role, unprivileged."
  }

  assert {
    condition     = strcontains(aws_codebuild_project.stage["prod-plan"].source[0].buildspec, "Destroy guard")
    error_message = "The plan buildspec must contain the destroy guard."
  }

  assert {
    condition     = strcontains(aws_codebuild_project.stage["prod-apply"].source[0].buildspec, "-detailed-exitcode")
    error_message = "The apply buildspec must check for a clean plan after apply."
  }
}

run "separate_target_account_for_prod" {
  variables {
    environments = {
      dev  = {}
      int  = {}
      prod = { account_id = "222222222222" }
    }
  }

  assert {
    condition = alltrue([
      for s in jsondecode(module.state_bucket.policy).Statement :
      s.Condition.StringEquals["aws:PrincipalArn"] == "arn:aws:iam::222222222222:role/demo-terraform-deployer-prod" if s.Effect == "Allow"
    ]) && length(jsondecode(module.state_bucket.policy).Statement) == 4
    error_message = "Only the prod deployer in the prod account gets bucket policy access, for its own state."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.codebuild["prod"].policy).Statement : s.Resource if s.Action == "sts:AssumeRole"
    ]) == "arn:aws:iam::222222222222:role/demo-terraform-deployer-prod"
    error_message = "The prod CodeBuild role must assume the deployer in the prod account."
  }

  assert {
    condition     = output.target_accounts["111111111111"] == tolist(["dev", "int"]) && output.target_accounts["222222222222"] == tolist(["prod"])
    error_message = "target_accounts output must group environments by account."
  }
}

run "optional_kms_key" {
  variables {
    create_kms_key = true
  }

  assert {
    condition     = length(aws_kms_key.cicd) == 1 && aws_kms_key.cicd[0].enable_key_rotation
    error_message = "With create_kms_key, one rotating key is created."
  }

  assert {
    condition     = aws_ecr_repository.tools["dev"].encryption_configuration[0].encryption_type == "KMS"
    error_message = "With create_kms_key, ECR uses the key."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environments = { staging = {} }
  }

  expect_failures = [var.environments]
}

run "rejects_bad_account_id" {
  command = plan

  variables {
    environments = { dev = { account_id = "12345" } }
  }

  expect_failures = [var.environments]
}
