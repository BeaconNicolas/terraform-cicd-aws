# GitHub Actions on github.com signs in with OpenID Connect, so no AWS keys are
# stored in GitHub. Each branch's workflow can only upload its own source.zip.

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://${local.github_oidc_host}"
}

locals {
  github_oidc_provider_arn = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

resource "aws_iam_role" "github" {
  for_each = local.envs

  name                 = each.value.github_role_name
  description          = "GitHub Actions (${var.github_owner}/${var.github_repo}, ${each.key}) uploads the ${each.key} source bundle."
  max_session_duration = 3600

  # The workflow job runs in the GitHub Environment named after the branch, so
  # GitHub sets the token subject to repo:<owner>/<repo>:environment:<env>.
  # The environment's deployment branch rule (README) allows only branch <env>.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_provider_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.github_oidc_host}:aud" = "sts.amazonaws.com"
          "${local.github_oidc_host}:sub" = "repo:${var.github_owner}/${var.github_repo}:environment:${each.key}"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github" {
  for_each = local.envs

  name = "upload-source"
  role = aws_iam_role.github[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Sid      = "PutOwnSourceBundleOnly"
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${module.source_bucket.arn}/${each.value.source_key}"
    }], local.kms_statements)
  })
}
