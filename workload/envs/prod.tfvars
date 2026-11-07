# Settings for the prod environment. No account IDs or emails here:
# project, environment and region come from the pipeline as TF_VAR_* variables.
app_message                       = "Hello from prod"
noncurrent_version_retention_days = 90

tags = {
  CostCentre = "demo"
}
