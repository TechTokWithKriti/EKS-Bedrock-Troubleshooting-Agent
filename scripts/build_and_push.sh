#!/usr/bin/env bash
# Builds both images for linux/amd64 (required even on Apple Silicon - the EKS nodes
# are t3.medium, i.e. x86_64) and pushes them to the single ECR repo created by
# Terraform, tagged orchestrator-<tag> and executor-<tag>.
#
# Usage: scripts/build_and_push.sh [tag]
#   tag defaults to the current short git SHA, or a timestamp if this isn't a git
#   checkout / there are no commits yet. The ECR repo has IMMUTABLE tags, so re-runs
#   need a new tag - re-running with the same explicit tag will fail on push, which is
#   intentional (silently overwriting a tag you might already be curling against is
#   worse than a loud failure).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd terraform docker aws

IMAGE_TAG="${1:-$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || date +%Y%m%d%H%M%S)}"

AWS_REGION="$(tf_output aws_region)"
ECR_REPO_URL="$(tf_output ecr_repository_url)"

echo "Logging in to ECR (${ECR_REPO_URL})..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REPO_URL%%/*}"

for component in orchestrator executor; do
  image="${ECR_REPO_URL}:${component}-${IMAGE_TAG}"
  echo "Building ${image}..."
  docker buildx build \
    --platform linux/amd64 \
    --tag "${image}" \
    --push \
    "${REPO_ROOT}/app/${component}"
  echo "Pushed ${image}"
done

cat <<EOF

Done. Image tag: ${IMAGE_TAG}
Render manifests with:
  scripts/render_manifests.sh ${IMAGE_TAG}
EOF
