#!/usr/bin/env bash
# Apply stage: apply exactly the plan that was approved, then check that a new
# plan shows no changes (terraform plan -detailed-exitcode must exit 0).
set -euo pipefail

check_tools_image
require_env DEPLOY_ENV CODEBUILD_SRC_DIR TF_VAR_project TF_VAR_environment TF_VAR_aws_region
# The input artifact is the Plan stage's output: the workload folder plus tfplan.
cd "${CODEBUILD_SRC_DIR}"

[[ -f tfplan && -f plan-meta.json ]] || fail "The plan artifact is missing tfplan or plan-meta.json."
plan_env="$(jq -r .environment plan-meta.json)"
[[ "${plan_env}" == "${DEPLOY_ENV}" ]] || fail "This plan was made for '${plan_env}', not '${DEPLOY_ENV}'."

assume_deployer
log "terraform init"
terraform_init

log "terraform apply (saved plan)"
terraform apply -input=false -lock-timeout=5m tfplan

log "Checking that the environment now matches the code"
rc=0
terraform plan -input=false -lock-timeout=5m -detailed-exitcode -var-file="envs/${DEPLOY_ENV}.tfvars" || rc=$?
case "${rc}" in
  0) log "No changes left. ${DEPLOY_ENV} is up to date." ;;
  2) fail "A plan after apply still shows changes. Check the resources above for drift or a provider issue." ;;
  *) fail "terraform plan failed after apply (exit code ${rc})." ;;
esac
