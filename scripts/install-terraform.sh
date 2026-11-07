#!/usr/bin/env bash
# Install the pinned Terraform (and optionally TFLint) into ~/bin, checking SHA256.
# Made for AWS CloudShell, works on any Linux x86_64 or arm64 machine.
#
#   ./scripts/install-terraform.sh            # Terraform only
#   ./scripts/install-terraform.sh --tflint   # Terraform and TFLint
#
# Versions and checksums come from tools-image/versions.env, the same file the
# pipeline's tools image uses, so CloudShell and the pipeline run the same versions.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=SCRIPTDIR/../tools-image/versions.env
source "${repo_root}/tools-image/versions.env"

install_dir="${INSTALL_DIR:-${HOME}/bin}"
mkdir -p "${install_dir}"

case "$(uname -m)" in
  x86_64) arch=amd64; tf_sum="${TERRAFORM_SHA256_AMD64}"; tflint_sum="${TFLINT_SHA256_AMD64}" ;;
  aarch64 | arm64) arch=arm64; tf_sum="${TERRAFORM_SHA256_ARM64}"; tflint_sum="${TFLINT_SHA256_ARM64}" ;;
  *) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

echo "Downloading Terraform ${TERRAFORM_VERSION} (linux_${arch})"
curl -fsSLo "${work}/terraform.zip" \
  "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"
echo "${tf_sum}  ${work}/terraform.zip" | sha256sum -c -
unzip -o -q "${work}/terraform.zip" terraform -d "${install_dir}"

if [[ "${1:-}" == "--tflint" ]]; then
  echo "Downloading TFLint ${TFLINT_VERSION} (linux_${arch})"
  curl -fsSLo "${work}/tflint.zip" \
    "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_${arch}.zip"
  echo "${tflint_sum}  ${work}/tflint.zip" | sha256sum -c -
  unzip -o -q "${work}/tflint.zip" tflint -d "${install_dir}"
fi

case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *) echo "Add ${install_dir} to your PATH:  export PATH=\"${install_dir}:\$PATH\"" ;;
esac

"${install_dir}/terraform" version
if [[ -x "${install_dir}/tflint" ]]; then "${install_dir}/tflint" --version; fi
