# Four CodeBuild projects per environment: image, test, plan and apply.
# All run on BUILD_GENERAL1_SMALL, the size the free tier covers.
#
# Buildspecs are generated here from ci/*.sh, not read from the repository, so
# a branch cannot switch off the destroy guard or the post-apply check. Change
# the scripts and re-apply this stack to change how the pipeline works.

locals {
  stage_script = {
    for stage in ["image", "test", "plan", "apply"] :
    stage => join("\n", [file("${path.module}/ci/lib.sh"), file("${path.module}/ci/${stage}.sh")])
  }

  exported_variables = {
    image = ["IMAGE_TAG"]
    test  = []
    plan  = ["PLAN_SUMMARY", "BUILD_URL"]
    apply = []
  }

  buildspec = {
    for stage, script in local.stage_script : stage => yamlencode(merge(
      {
        version = 0.2
        env = merge(
          { shell = "bash" },
          length(local.exported_variables[stage]) > 0 ? { "exported-variables" = local.exported_variables[stage] } : {},
        )
        phases = {
          build = {
            commands = [
              # Write the stage script to a file and run it in its own bash
              # process, then load the values it exported for CodePipeline.
              "cat > /tmp/ci-stage.sh <<'CI_STAGE_EOF'\n${script}\nCI_STAGE_EOF",
              "bash /tmp/ci-stage.sh",
              "set -a; . /tmp/ci-exports.env; set +a",
            ]
          }
        }
      },
      # Plan hands the workload folder (without .terraform) and tfplan to Apply.
      stage == "plan" ? { artifacts = { "base-directory" = "workload", files = ["**/*"] } } : {},
    ))
  }
}

resource "aws_cloudwatch_log_group" "codebuild" {
  for_each = local.codebuild_projects

  name              = "/aws/codebuild/${each.value.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_codebuild_project" "stage" {
  for_each = local.codebuild_projects

  name          = each.value.name
  description   = "${each.value.stage} stage of the ${each.value.env} pipeline"
  service_role  = aws_iam_role.codebuild[each.value.env].arn
  build_timeout = each.value.stage == "image" ? 30 : 20

  source {
    type      = "CODEPIPELINE"
    buildspec = local.buildspec[each.value.stage]
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"

    # The image stage needs Docker (privileged). The others run the tools image,
    # pulled from this environment's ECR repository with the service role.
    image                       = each.value.stage == "image" ? var.codebuild_image : "${aws_ecr_repository.tools[each.value.env].repository_url}:current"
    image_pull_credentials_type = each.value.stage == "image" ? "CODEBUILD" : "SERVICE_ROLE"
    privileged_mode             = each.value.stage == "image"

    dynamic "environment_variable" {
      for_each = {
        DEPLOY_ENV          = each.value.env
        TF_VAR_project      = local.p
        TF_VAR_environment  = each.value.env
        TF_VAR_aws_region   = local.region
        DEPLOYER_ROLE_ARN   = local.envs[each.value.env].deployer_role_arn
        STATE_BUCKET        = module.state_bucket.id
        STATE_KEY           = local.envs[each.value.env].state_key
        STATE_REGION        = local.region
        ECR_REPOSITORY_NAME = aws_ecr_repository.tools[each.value.env].name
        ECR_REPOSITORY_URI  = aws_ecr_repository.tools[each.value.env].repository_url
      }
      content {
        name  = environment_variable.key
        value = environment_variable.value
      }
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild[each.key].name
    }
  }

  encryption_key = local.kms_key_arn

  depends_on = [aws_iam_role_policy.codebuild]
}
