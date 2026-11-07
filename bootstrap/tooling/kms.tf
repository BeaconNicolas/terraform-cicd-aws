# Optional customer-managed key. Off by default because a CMK is billed monthly
# even when nothing uses it; SSE-S3 is free and is what the buckets use otherwise.

resource "aws_kms_key" "cicd" {
  count = var.create_kms_key ? 1 : 0

  description             = "${local.p} CI/CD buckets and pipeline artifacts"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid       = "AccountAdministersKeyThroughIam"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      }],
      [for env, e in local.envs : {
        Sid       = "Deployer${title(env)}UsesKeyForState"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${e.target_account_id}:root" }
        Action    = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:PrincipalArn" = e.deployer_role_arn } }
      } if e.cross_account]
    )
  })
}

resource "aws_kms_alias" "cicd" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${local.p}-cicd"
  target_key_id = aws_kms_key.cicd[0].key_id
}
