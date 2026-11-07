# Offline tests: the AWS provider is mocked, so no credentials or API calls are needed.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }
}

variables {
  project     = "demo"
  environment = "dev"
  aws_region  = "eu-west-1"
  app_message = "hello"
}

run "names_follow_the_convention" {
  command = plan

  assert {
    condition     = aws_s3_bucket.app.bucket == "demo-dev-app-111111111111-eu-west-1"
    error_message = "Bucket name must be <project>-<env>-app-<account>-<region>; the deployer role's permissions depend on it."
  }

  assert {
    condition     = aws_ssm_parameter.app_message.name == "/demo/dev/app-message"
    error_message = "Parameter must live under /<project>/<env>/; the deployer role's permissions depend on it."
  }
}

run "bucket_is_private_versioned_and_encrypted" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.app.block_public_acls,
      aws_s3_bucket_public_access_block.app.block_public_policy,
      aws_s3_bucket_public_access_block.app.ignore_public_acls,
      aws_s3_bucket_public_access_block.app.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = aws_s3_bucket_versioning.app.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.app.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Bucket must use SSE-S3 (no customer-managed KMS key, so nothing is billed while idle)."
  }

  assert {
    condition     = aws_s3_bucket.app.force_destroy == false
    error_message = "force_destroy must default to false."
  }
}

run "app_message_is_stored" {
  command = plan

  variables {
    environment = "prod"
    app_message = "from prod"
  }

  assert {
    condition     = aws_ssm_parameter.app_message.value == "from prod"
    error_message = "app_message must be written to the parameter."
  }
}

run "rejects_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "rejects_long_project_name" {
  command = plan

  variables {
    project = "this-name-is-far-too-long"
  }

  expect_failures = [var.project]
}
