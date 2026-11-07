#!/usr/bin/env bash
# Plan stage: format check, lint, init, validate and a saved plan for this
# environment, followed by the destroy guard. The plan is the stage's artifact.
set -euo pipefail

check_tools_image
require_env DEPLOY_ENV CODEBUILD_SRC_DIR TF_VAR_project TF_VAR_environment TF_VAR_aws_region
cd "${CODEBUILD_SRC_DIR}"

log "terraform fmt -check"
terraform fmt -check -recursive -diff

cd workload
var_file="envs/${DEPLOY_ENV}.tfvars"
[[ -f "${var_file}" ]] || fail "workload/${var_file} is missing."

log "tflint"
tflint_config=()
[[ -f "${CODEBUILD_SRC_DIR}/.tflint.hcl" ]] && tflint_config=(--config "${CODEBUILD_SRC_DIR}/.tflint.hcl")
tflint "${tflint_config[@]}" --format compact

assume_deployer
log "terraform init"
terraform_init
log "terraform validate"
terraform validate

log "terraform plan"
terraform plan -input=false -lock-timeout=5m -var-file="${var_file}" -out=tfplan
terraform show -json tfplan >/tmp/plan.json

# Destroy guard: the pipeline never deletes or replaces anything. Deletions
# are done on purpose, by a person, outside the pipeline (README: Teardown).
deletes="$(jq -r '.resource_changes[]? | select(.change.actions | index("delete")) | "  - \(.address) (\(.change.actions | join(" then ")))"' /tmp/plan.json)"
if [[ -n "${deletes}" ]]; then
  printf '\nThese resources would be deleted or replaced:\n%s\n' "${deletes}" >&2
  fail "Destroy guard: the plan deletes or replaces resources, so the pipeline stops here."
fi

summary="$(jq -r '
  [.resource_changes[]?.change.actions] as $a
  | "\($a | map(select(. == ["create"])) | length) to add, \($a | map(select(. == ["update"])) | length) to change, 0 to destroy"' /tmp/plan.json)"
log "Plan: ${summary}"

jq -n --arg env "${DEPLOY_ENV}" --arg source "${SOURCE_VERSION_ID:-unknown}" --arg build "${CODEBUILD_BUILD_ID:-local}" \
  '{environment: $env, source_version_id: $source, plan_build_id: $build}' >plan-meta.json

# Keep the artifact small: Apply runs terraform init again.
rm -rf .terraform

export_var PLAN_SUMMARY "${summary}"
export_var BUILD_URL "${CODEBUILD_BUILD_URL:-}"
