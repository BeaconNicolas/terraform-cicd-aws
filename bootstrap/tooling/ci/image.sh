#!/usr/bin/env bash
# Tools image stage: build tools-image/ into ECR unless an image with the same
# content hash is already there, then point the "current" tag at it.
# Runs on the CodeBuild standard image (privileged, for Docker).
set -euo pipefail

require_env ECR_REPOSITORY_NAME ECR_REPOSITORY_URI CODEBUILD_SRC_DIR
cd "${CODEBUILD_SRC_DIR}"

image_dir="tools-image"
[[ -f "${image_dir}/Dockerfile" && -f "${image_dir}/versions.env" ]] ||
  fail "${image_dir}/Dockerfile or ${image_dir}/versions.env is missing from the source bundle."

# Hash of every file name and content in the folder, in a stable order.
content_hash="$(cd "${image_dir}" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)"
tag="sha-${content_hash}"
log "Tools image tag ${tag}"

image_digest() {
  aws ecr describe-images --repository-name "${ECR_REPOSITORY_NAME}" --image-ids "imageTag=$1" \
    --query 'imageDetails[0].imageDigest' --output text 2>/dev/null || true
}

if [[ -n "$(image_digest "${tag}")" ]]; then
  log "${tag} already exists in ECR, skipping the build"
else
  log "Building ${tag}"
  registry="${ECR_REPOSITORY_URI%%/*}"
  aws ecr get-login-password | docker login --username AWS --password-stdin "${registry}"

  build_args=(--build-arg "TOOLS_IMAGE_TAG=${tag}")
  while IFS='=' read -r key value || [[ -n "${key}" ]]; do
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    build_args+=(--build-arg "${key}=${value}")
  done <"${image_dir}/versions.env"

  docker build --pull "${build_args[@]}" -t "${ECR_REPOSITORY_URI}:${tag}" "${image_dir}"
  docker push "${ECR_REPOSITORY_URI}:${tag}"
fi

# Move "current" (the only mutable tag) to this image, reusing its manifest so
# nothing is rebuilt or re-uploaded.
tag_digest="$(image_digest "${tag}")"
if [[ "$(image_digest current)" != "${tag_digest}" ]]; then
  get_image() {
    aws ecr batch-get-image --repository-name "${ECR_REPOSITORY_NAME}" --image-ids "imageTag=${tag}" \
      --query "images[0].$1" --output text
  }
  aws ecr put-image --repository-name "${ECR_REPOSITORY_NAME}" --image-tag current \
    --image-manifest "$(get_image imageManifest)" \
    --image-manifest-media-type "$(get_image imageManifestMediaType)" >/dev/null
  log "current -> ${tag} (${tag_digest})"
else
  log "current already points at ${tag}"
fi

export_var IMAGE_TAG "${tag}"
