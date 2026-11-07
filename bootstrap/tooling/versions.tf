terraform {
  required_version = "~> 1.17.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.72.0"
    }
  }

  # State starts local. After the first apply, the README shows how to move it
  # into the state bucket this stack creates (backend.tf, which git ignores).
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(var.tags, {
      Project   = var.project
      Stack     = "bootstrap-tooling"
      ManagedBy = "terraform"
    })
  }
}
