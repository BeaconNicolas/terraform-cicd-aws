terraform {
  required_version = "~> 1.17.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.72.0"
    }
  }

  # State starts local; see the README for moving it into the state bucket.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project   = var.project
      Stack     = "bootstrap-target"
      ManagedBy = "terraform"
    })
  }
}
