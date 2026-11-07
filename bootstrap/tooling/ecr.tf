# One repository per environment for the tools image. Tags are immutable,
# except "current", which the Tools image stage moves to the image of the
# running execution (Test, Plan and Apply run "current"; see ci/image.sh).

resource "aws_ecr_repository" "tools" {
  for_each = local.envs

  name                 = each.value.ecr_repository_name
  image_tag_mutability = "IMMUTABLE_WITH_EXCLUSION"
  force_delete         = var.force_destroy

  image_tag_mutability_exclusion_filter {
    filter      = "current"
    filter_type = "WILDCARD"
  }

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.create_kms_key ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn
  }
}

resource "aws_ecr_lifecycle_policy" "tools" {
  for_each = local.envs

  repository = aws_ecr_repository.tools[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Remove untagged images after a day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the three newest tools images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 3
        }
        action = { type = "expire" }
      },
    ]
  })
}
