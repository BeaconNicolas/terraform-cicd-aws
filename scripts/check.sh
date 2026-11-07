#!/usr/bin/env bash
# Run the offline checks on every Terraform stack in this repository:
# fmt, init (no backend), validate, TFLint (if installed) and terraform test.
# Needs no AWS credentials: the tests use mock providers.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

stacks=(workload bootstrap/tooling bootstrap/target)

echo "== terraform fmt -check"
terraform fmt -check -recursive -diff

for stack in "${stacks[@]}"; do
  echo "== ${stack}"
  terraform -chdir="${stack}" init -backend=false -input=false >/dev/null
  terraform -chdir="${stack}" validate
  if command -v tflint >/dev/null 2>&1; then
    (cd "${stack}" && tflint --config "${repo_root}/.tflint.hcl" --format compact)
  else
    echo "tflint not installed, skipping lint (./scripts/install-terraform.sh --tflint)"
  fi
  terraform -chdir="${stack}" test
done

echo "All checks passed."
