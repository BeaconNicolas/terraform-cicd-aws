# Settings for the int environment. No account IDs or emails here:
# project, environment and region come from the pipeline as TF_VAR_* variables.
app_message                       = "Hello from int"
noncurrent_version_retention_days = 7

tags = {
  CostCentre = "demo"
}
