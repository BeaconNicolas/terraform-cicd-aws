# Copy to terraform.tfvars (git ignores it) and fill in values from the
# outputs of bootstrap/tooling.

aws_region   = "eu-west-1"                           # same region as bootstrap/tooling
state_bucket = "tfcicd-tfstate-ACCOUNT_ID-eu-west-1" # state_bucket output

# Single account: keep all environments and leave tooling_account_id unset.
environments = ["dev", "int", "prod"]

# Separate target account, e.g. prod only:
# environments       = ["prod"]
# tooling_account_id = "111111111111"     # tooling_account_id output
# create_budget      = true
# notification_email = "you@example.com"
