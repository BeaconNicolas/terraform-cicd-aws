output "deployer_role_arns" {
  description = "Deployer role per environment hosted in this account."
  value       = { for env, role in aws_iam_role.deployer : env => role.arn }
}
