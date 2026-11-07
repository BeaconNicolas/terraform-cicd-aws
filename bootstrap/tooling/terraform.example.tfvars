# Copy to terraform.tfvars (git ignores it) and fill in your values.

aws_region   = "eu-west-1" # pick your region; see the README before choosing af-south-1
github_owner = "your-github-user"
github_repo  = "terraform-cicd-aws"

notification_email = "you@example.com" # approval requests and budget alerts
budget_limit_usd   = 5

# Single account: leave account_id out and everything lives in this account.
environments = {
  dev  = {}
  int  = {}
  prod = {}
}

# Separate target accounts (run bootstrap/target in each one afterwards):
# environments = {
#   dev  = { account_id = "111111111111" }
#   int  = { account_id = "222222222222" }
#   prod = { account_id = "333333333333" }
# }

# Set to true just before teardown so destroy can empty buckets and ECR.
force_destroy = false
