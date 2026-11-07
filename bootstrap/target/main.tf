# Target account: one deployer role per environment hosted here. Each trusts
# only that environment's CodeBuild role in the tooling account and may only
# manage that environment's state and the example workload's resources.
#
# Apply bootstrap/tooling first: IAM rejects a trust policy whose principal
# role does not exist yet.

data "aws_caller_identity" "current" {}

locals {
  account_id         = data.aws_caller_identity.current.account_id
  tooling_account_id = coalesce(var.tooling_account_id, local.account_id)
  region             = var.aws_region
  p                  = var.project
  state_bucket_arn   = "arn:aws:s3:::${var.state_bucket}"
}

resource "aws_iam_role" "deployer" {
  for_each = var.environments

  name                 = "${local.p}-terraform-deployer-${each.key}"
  description          = "Terraform for the ${each.key} pipeline. No delete permissions: the pipeline never destroys."
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OwnEnvironmentCodeBuildRoleOnly"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${local.tooling_account_id}:role/${local.p}-cicd-codebuild-${each.key}" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "deployer" {
  for_each = var.environments

  name = "terraform-${each.key}"
  role = aws_iam_role.deployer[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        # ---- Terraform state: this environment's key and lock file only.
        {
          Sid       = "ListOwnState"
          Effect    = "Allow"
          Action    = "s3:ListBucket"
          Resource  = local.state_bucket_arn
          Condition = { StringLike = { "s3:prefix" = "workload/${each.key}.tfstate*" } }
        },
        {
          Sid      = "ReadWriteOwnState"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject"]
          Resource = "${local.state_bucket_arn}/workload/${each.key}.tfstate"
        },
        {
          Sid      = "ManageOwnLockFile"
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          Resource = "${local.state_bucket_arn}/workload/${each.key}.tfstate.tflock"
        },
        # ---- Example workload: its bucket (bucket-level settings, never
        # objects) and its parameters. No DeleteBucket or DeleteParameter.
        {
          Sid    = "ManageWorkloadBucket"
          Effect = "Allow"
          Action = [
            "s3:CreateBucket",
            "s3:Get*",
            "s3:List*",
            "s3:PutBucket*",
            "s3:PutEncryptionConfiguration",
            "s3:PutLifecycleConfiguration",
            "s3:TagResource",
            "s3:UntagResource",
          ]
          Resource = "arn:aws:s3:::${local.p}-${each.key}-app-*"
        },
        {
          Sid    = "ManageWorkloadParameters"
          Effect = "Allow"
          Action = [
            "ssm:AddTagsToResource",
            "ssm:GetParameter",
            "ssm:GetParameters",
            "ssm:ListTagsForResource",
            "ssm:PutParameter",
            "ssm:RemoveTagsFromResource",
          ]
          Resource = "arn:aws:ssm:${local.region}:${local.account_id}:parameter/${local.p}/${each.key}/*"
        },
        {
          # DescribeParameters has no resource-level permissions.
          Sid      = "DescribeParameters"
          Effect   = "Allow"
          Action   = "ssm:DescribeParameters"
          Resource = "*"
        },
      ],
      var.state_kms_key_arn == null ? [] : [{
        Sid      = "UseStateKey"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource = var.state_kms_key_arn
      }],
    )
  })
}

resource "aws_budgets_budget" "monthly" {
  count = var.create_budget ? 1 : 0

  name         = "${local.p}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }

  lifecycle {
    precondition {
      condition     = var.notification_email != null
      error_message = "Set notification_email when create_budget is true."
    }
  }
}
