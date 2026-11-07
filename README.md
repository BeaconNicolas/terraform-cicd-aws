# terraform-cicd-aws

A reference implementation of a Terraform CI/CD pipeline on AWS with a GitHub trigger.
A merge to `dev`, `int` or `prod` becomes a reviewed, approved `terraform apply`, using
GitHub OIDC (no long-lived AWS keys) and one AWS CodePipeline per environment.

Work in progress.

## Branches

| Branch | Environment |
| ------ | ----------- |
| `dev`  | development |
| `int`  | integration |
| `prod` | production  |

Changes are promoted by pull request: `dev` → `int` → `prod`.
