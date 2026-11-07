# Service roles, one set per environment. Each trusts only its own service
# principal, and only when the request comes from this account and from the
# exact pipeline, CodeBuild project or EventBridge rule (confused-deputy guard).

# ---------------------------------------------------------------- CodePipeline
resource "aws_iam_role" "pipeline" {
  for_each = local.envs

  name = each.value.pipeline_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = each.value.pipeline_arn
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "pipeline" {
  for_each = local.envs

  name = "pipeline"
  role = aws_iam_role.pipeline[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "ReadOwnSourceBundle"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${module.source_bucket.arn}/${each.value.source_key}"
      },
      {
        Sid      = "InspectBuckets"
        Effect   = "Allow"
        Action   = ["s3:GetBucketVersioning", "s3:GetBucketLocation", "s3:GetBucketAcl", "s3:ListBucket"]
        Resource = [module.source_bucket.arn, module.artifact_bucket[each.key].arn]
      },
      {
        Sid      = "ReadWriteOwnArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${module.artifact_bucket[each.key].arn}/*"
      },
      {
        Sid      = "RunOwnBuilds"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds", "codebuild:StopBuild"]
        Resource = [for name in values(each.value.codebuild_projects) : "arn:aws:codebuild:${local.region}:${local.account_id}:project/${name}"]
      },
      {
        Sid      = "NotifyApprovers"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.approvals[each.key].arn
      },
    ], local.kms_statements)
  })
}

# ------------------------------------------------------------------- CodeBuild
resource "aws_iam_role" "codebuild" {
  for_each = local.envs

  name = each.value.codebuild_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = [for name in values(each.value.codebuild_projects) : "arn:aws:codebuild:${local.region}:${local.account_id}:project/${name}"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codebuild" {
  for_each = local.envs

  name = "codebuild"
  role = aws_iam_role.codebuild[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for name in values(each.value.codebuild_projects) : "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/codebuild/${name}:*"]
      },
      {
        Sid      = "ReadWriteOwnArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = "${module.artifact_bucket[each.key].arn}/*"
      },
      {
        Sid      = "InspectOwnArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketAcl", "s3:GetBucketLocation"]
        Resource = module.artifact_bucket[each.key].arn
      },
      {
        # GetAuthorizationToken has no resource-level permissions.
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PullPushOwnToolsImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeImages",
          "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
        ]
        Resource = aws_ecr_repository.tools[each.key].arn
      },
      {
        Sid      = "AssumeOwnDeployerOnly"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = each.value.deployer_role_arn
      },
    ], local.kms_statements)
  })
}

# ----------------------------------------------------------------- EventBridge
resource "aws_iam_role" "events" {
  for_each = local.envs

  name = each.value.events_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = each.value.event_rule_arn
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "events" {
  for_each = local.envs

  name = "start-pipeline"
  role = aws_iam_role.events[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "StartOwnPipelineOnly"
      Effect   = "Allow"
      Action   = "codepipeline:StartPipelineExecution"
      Resource = each.value.pipeline_arn
    }]
  })
}
