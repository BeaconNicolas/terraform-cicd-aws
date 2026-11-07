#!/usr/bin/env bash
# Test stage: run `terraform test` for every stack that has a tests/ folder.
# The tests use mock providers, so this stage needs no AWS permissions.
set -euo pipefail

check_tools_image
cd "${CODEBUILD_SRC_DIR}"

mapfile -t stacks < <(
  find . -path '*/.terraform' -prune -o -type d -name tests -print |
    while read -r dir; do
      parent="$(dirname "${dir}")"
      compgen -G "${parent}/*.tf" >/dev/null && echo "${parent#./}"
    done | LC_ALL=C sort
)
[[ ${#stacks[@]} -gt 0 ]] || fail "No stacks with tests found."

for stack in "${stacks[@]}"; do
  log "terraform test: ${stack}"
  terraform -chdir="${stack}" init -backend=false -input=false >/dev/null
  terraform -chdir="${stack}" test
done
