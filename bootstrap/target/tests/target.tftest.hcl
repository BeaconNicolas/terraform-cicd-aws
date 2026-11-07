# Offline tests for the target stack (mocked AWS provider, no API calls).

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "222222222222"
    }
  }
}

variables {
  project      = "demo"
  aws_region   = "eu-west-1"
  state_bucket = "demo-tfstate-111111111111-eu-west-1"
}

run "single_account" {
  assert {
    condition     = length(aws_iam_role.deployer) == 3 && length(aws_budgets_budget.monthly) == 0
    error_message = "One deployer per environment, and no extra budget by default."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deployer["dev"].assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::222222222222:role/demo-cicd-codebuild-dev"
    error_message = "With no tooling account set, the dev deployer trusts the dev CodeBuild role in this account."
  }
}

run "separate_accounts" {
  variables {
    environments       = ["prod"]
    tooling_account_id = "111111111111"
    create_budget      = true
    notification_email = "alerts@example.com"
  }

  assert {
    condition     = keys(aws_iam_role.deployer) == ["prod"]
    error_message = "Only the prod deployer lives in this account."
  }

  assert {
    condition     = jsondecode(aws_iam_role.deployer["prod"].assume_role_policy).Statement[0].Principal.AWS == "arn:aws:iam::111111111111:role/demo-cicd-codebuild-prod"
    error_message = "The prod deployer must trust only the prod CodeBuild role in the tooling account."
  }

  assert {
    condition     = length(aws_budgets_budget.monthly) == 1
    error_message = "create_budget adds a budget for this account."
  }
}

run "deployer_cannot_delete_or_escalate" {
  assert {
    condition = alltrue(flatten([
      for s in jsondecode(aws_iam_role_policy.deployer["prod"].policy).Statement : [
        for a in flatten([s.Action]) : !can(regex("^(iam:|sts:|s3:DeleteBucket|ssm:DeleteParameter|\\*)", a))
      ]
    ]))
    error_message = "The deployer must have no IAM/STS permissions and cannot delete the workload bucket or parameters."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.deployer["prod"].policy).Statement :
      s.Resource == "*" ? s.Action == "ssm:DescribeParameters" : true
    ])
    error_message = "Only ssm:DescribeParameters may use Resource \"*\"."
  }

  assert {
    condition = one([
      for s in jsondecode(aws_iam_role_policy.deployer["prod"].policy).Statement : s.Resource if s.Sid == "ReadWriteOwnState"
    ]) == "arn:aws:s3:::demo-tfstate-111111111111-eu-west-1/workload/prod.tfstate"
    error_message = "The prod deployer may only read and write the prod state key."
  }
}

run "budget_needs_email" {
  command = plan

  variables {
    create_budget = true
  }

  expect_failures = [aws_budgets_budget.monthly]
}
