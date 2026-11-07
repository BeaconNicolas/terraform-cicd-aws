# One CodePipeline (V2) per environment:
# Source -> Tools image -> Test -> Plan -> Approve -> Apply.

resource "aws_sns_topic" "approvals" {
  for_each = local.envs

  name              = "${local.p}-cicd-approvals-${each.key}"
  kms_master_key_id = local.kms_key_arn
}

resource "aws_sns_topic_subscription" "approvals_email" {
  for_each = local.envs

  topic_arn = aws_sns_topic.approvals[each.key].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_codepipeline" "this" {
  for_each = local.envs

  name           = each.value.pipeline_name
  role_arn       = aws_iam_role.pipeline[each.key].arn
  pipeline_type  = "V2"
  execution_mode = "QUEUED" # one run at a time per environment, in order

  artifact_store {
    location = module.artifact_bucket[each.key].id
    type     = "S3"

    dynamic "encryption_key" {
      for_each = var.create_kms_key ? [local.kms_key_arn] : []
      content {
        id   = encryption_key.value
        type = "KMS"
      }
    }
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      namespace        = "SOURCE"
      output_artifacts = ["source"]

      configuration = {
        S3Bucket    = module.source_bucket.id
        S3ObjectKey = each.value.source_key
        # EventBridge starts the pipeline; no polling.
        PollForSourceChanges = "false"
      }
    }
  }

  stage {
    name = "ToolsImage"

    action {
      name            = "BuildToolsImage"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      namespace       = "TOOLS"
      input_artifacts = ["source"]

      configuration = {
        ProjectName = aws_codebuild_project.stage["${each.key}-image"].name
      }
    }
  }

  stage {
    name = "Test"

    action {
      name            = "TerraformTest"
      category        = "Test"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]

      configuration = {
        ProjectName = aws_codebuild_project.stage["${each.key}-test"].name
        EnvironmentVariables = jsonencode([
          { name = "EXPECTED_TOOLS_IMAGE_TAG", value = "#{TOOLS.IMAGE_TAG}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  stage {
    name = "Plan"

    action {
      name             = "TerraformPlan"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      namespace        = "PLAN"
      input_artifacts  = ["source"]
      output_artifacts = ["plan"]

      configuration = {
        ProjectName = aws_codebuild_project.stage["${each.key}-plan"].name
        EnvironmentVariables = jsonencode([
          { name = "EXPECTED_TOOLS_IMAGE_TAG", value = "#{TOOLS.IMAGE_TAG}", type = "PLAINTEXT" },
          { name = "SOURCE_VERSION_ID", value = "#{SOURCE.VersionId}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  stage {
    name = "Approve"

    action {
      name     = "ReviewPlan"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        NotificationArn    = aws_sns_topic.approvals[each.key].arn
        CustomData         = "Terraform plan for ${each.key}: #{PLAN.PLAN_SUMMARY}. Open the link to read the full plan log before you approve."
        ExternalEntityLink = "#{PLAN.BUILD_URL}"
      }
    }
  }

  stage {
    name = "Apply"

    action {
      name            = "TerraformApply"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["plan"]

      configuration = {
        ProjectName = aws_codebuild_project.stage["${each.key}-apply"].name
        EnvironmentVariables = jsonencode([
          { name = "EXPECTED_TOOLS_IMAGE_TAG", value = "#{TOOLS.IMAGE_TAG}", type = "PLAINTEXT" },
        ])
      }
    }
  }

  depends_on = [aws_iam_role_policy.pipeline]
}

# An upload of exactly <env>/source.zip starts exactly that env's pipeline.
resource "aws_cloudwatch_event_rule" "source" {
  for_each = local.envs

  name        = each.value.event_rule_name
  description = "Start the ${each.key} pipeline when GitHub Actions uploads ${each.value.source_key}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [module.source_bucket.id] }
      object = { key = [each.value.source_key] }
    }
  })
}

resource "aws_cloudwatch_event_target" "pipeline" {
  for_each = local.envs

  rule     = aws_cloudwatch_event_rule.source[each.key].name
  arn      = aws_codepipeline.this[each.key].arn
  role_arn = aws_iam_role.events[each.key].arn

  depends_on = [aws_iam_role_policy.events]
}
