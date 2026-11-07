# Tools image used by the Test, Plan and Apply stages.
# Every tool is pinned to a version and checked against a SHA256.
# The pipeline tags the image with a hash of this folder, so any change here
# produces a new image; an unchanged folder reuses the existing one.

# Amazon Linux 2023 from the ECR Public Gallery (avoids Docker Hub rate limits).
FROM public.ecr.aws/amazonlinux/amazonlinux:2023.12.20261102.0@sha256:381352c430f36d8aa6b8b670de06e7e4e5642fe0cb9dbd463bb8d1e79aefc0c7

ARG TERRAFORM_VERSION
ARG TERRAFORM_SHA256_AMD64
ARG TFLINT_VERSION
ARG TFLINT_SHA256_AMD64
ARG AWSCLI_VERSION
ARG AWSCLI_SHA256_AMD64
ARG JQ_VERSION
ARG JQ_SHA256_AMD64
ARG TOOLS_IMAGE_TAG=unknown

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN dnf install -y --setopt=install_weak_deps=False unzip tar gzip findutils git-core \
    && dnf clean all \
    && rm -rf /var/cache/dnf

WORKDIR /tmp/tools

RUN test -n "${TERRAFORM_VERSION}" || { echo "Build args missing: pass tools-image/versions.env as --build-arg values" >&2; exit 1; } \
    # Terraform
    && curl -fsSLo terraform.zip "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    && echo "${TERRAFORM_SHA256_AMD64}  terraform.zip" | sha256sum -c - \
    && unzip -q terraform.zip terraform -d /usr/local/bin \
    # TFLint
    && curl -fsSLo tflint.zip "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    && echo "${TFLINT_SHA256_AMD64}  tflint.zip" | sha256sum -c - \
    && unzip -q tflint.zip tflint -d /usr/local/bin \
    # AWS CLI v2
    && curl -fsSLo awscli.zip "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip" \
    && echo "${AWSCLI_SHA256_AMD64}  awscli.zip" | sha256sum -c - \
    && unzip -q awscli.zip \
    && ./aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli \
    # jq
    && curl -fsSLo /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
    && echo "${JQ_SHA256_AMD64}  /usr/local/bin/jq" | sha256sum -c - \
    && chmod 0755 /usr/local/bin/jq \
    && cd / && rm -rf /tmp/tools \
    && terraform version && tflint --version && aws --version && jq --version

# Later stages compare this to the tag the Tools image stage reported, to be
# sure they run on the image built for this exact pipeline execution.
RUN echo "${TOOLS_IMAGE_TAG}" > /etc/tools-image-tag

ENV CHECKPOINT_DISABLE=1 \
    TF_IN_AUTOMATION=1 \
    TF_INPUT=0

WORKDIR /
