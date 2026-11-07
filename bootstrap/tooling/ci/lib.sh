#!/usr/bin/env bash
# Shared helpers for the CodeBuild stages. The buildspec joins this file and
# one stage script into a single script and runs it with bash.
set -euo pipefail

# Values written here become CodePipeline output variables (exported-variables).
CI_EXPORTS_FILE="${CI_EXPORTS_FILE:-/tmp/ci-exports.env}"
: >"${CI_EXPORTS_FILE}"

# Share downloaded providers between the stacks of one build.
export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-/tmp/terraform-plugin-cache}"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"
export TF_IN_AUTOMATION=1 TF_INPUT=0 CHECKPOINT_DISABLE=1

log() { printf '\n==> %s\n' "$*"; }

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

export_var() {
  printf '%s=%q\n' "$1" "$2" >>"${CI_EXPORTS_FILE}"
}

require_env() {
  local name
  for name in "$@"; do
    [[ -n "${!name:-}" ]] || fail "Environment variable ${name} is not set on this CodeBuild project."
  done
}

# Test, Plan and Apply run the "current" tools image. Make sure it is the one
# the Tools image stage of this same pipeline execution produced.
check_tools_image() {
  local expected="${EXPECTED_TOOLS_IMAGE_TAG:-}" actual
  actual="$(cat /etc/tools-image-tag 2>/dev/null || echo missing)"
  [[ -n "${expected}" ]] || fail "The pipeline did not pass EXPECTED_TOOLS_IMAGE_TAG."
  if [[ "${actual}" != "${expected}" ]]; then
    fail "This build runs tools image '${actual}', but this execution built '${expected}'. Retry the stage."
  fi
  log "Tools image ${actual}"
}

assume_deployer() {
  require_env DEPLOYER_ROLE_ARN DEPLOY_ENV
  log "Assuming ${DEPLOYER_ROLE_ARN}"
  local creds
  creds="$(aws sts assume-role \
    --role-arn "${DEPLOYER_ROLE_ARN}" \
    --role-session-name "codebuild-${DEPLOY_ENV}-${CODEBUILD_BUILD_NUMBER:-0}" \
    --duration-seconds 3600 \
    --query Credentials --output json)"
  AWS_ACCESS_KEY_ID="$(jq -r .AccessKeyId <<<"${creds}")"
  AWS_SECRET_ACCESS_KEY="$(jq -r .SecretAccessKey <<<"${creds}")"
  AWS_SESSION_TOKEN="$(jq -r .SessionToken <<<"${creds}")"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  aws sts get-caller-identity --query Arn --output text
}

terraform_init() {
  require_env STATE_BUCKET STATE_KEY STATE_REGION
  terraform init -input=false \
    -backend-config="bucket=${STATE_BUCKET}" \
    -backend-config="key=${STATE_KEY}" \
    -backend-config="region=${STATE_REGION}"
}
