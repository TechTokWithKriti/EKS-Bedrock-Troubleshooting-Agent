#!/usr/bin/env bash
# Renders k8s/*.yaml templates into k8s/rendered/ (gitignored) by substituting
# ${VAR} placeholders with values pulled from `terraform output` and the image tag
# you built with. Uses python3's string.Template instead of envsubst so this doesn't
# pick up an extra host dependency - `substitute` (not `safe_substitute`) means a
# placeholder with no matching value fails loudly instead of being applied literally.
#
# Usage: scripts/render_manifests.sh <image-tag>
#   <image-tag> must match what scripts/build_and_push.sh produced.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd terraform python3

if [ -z "${1:-}" ]; then
  echo "usage: $0 <image-tag>" >&2
  exit 1
fi
IMAGE_TAG="$1"

AWS_REGION="$(tf_output aws_region)"
ECR_REPO_URL="$(tf_output ecr_repository_url)"
ORCHESTRATOR_ROLE_ARN="$(tf_output orchestrator_role_arn)"
BEDROCK_INFERENCE_PROFILE_ID="$(tf_output bedrock_inference_profile_id)"

RENDERED_DIR="${REPO_ROOT}/k8s/rendered"
mkdir -p "${RENDERED_DIR}"
rm -f "${RENDERED_DIR}"/*.yaml

export AWS_REGION ORCHESTRATOR_ROLE_ARN BEDROCK_INFERENCE_PROFILE_ID
export ORCHESTRATOR_IMAGE="${ECR_REPO_URL}:orchestrator-${IMAGE_TAG}"
export EXECUTOR_IMAGE="${ECR_REPO_URL}:executor-${IMAGE_TAG}"

for template in "${REPO_ROOT}"/k8s/*.yaml; do
  name="$(basename "${template}")"
  python3 - "${template}" "${RENDERED_DIR}/${name}" <<'PY'
import os
import string
import sys

src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    text = f.read()

keys = ("AWS_REGION", "ORCHESTRATOR_ROLE_ARN", "BEDROCK_INFERENCE_PROFILE_ID",
        "ORCHESTRATOR_IMAGE", "EXECUTOR_IMAGE")
values = {k: os.environ[k] for k in keys if k in os.environ}

# strict substitute: files with no ${...} placeholders pass through unchanged either
# way, but a file that DOES reference a placeholder missing from `values` raises
# instead of being applied with the literal "${TYPO}" left in it.
rendered = string.Template(text).substitute(values)
with open(dst, "w") as f:
    f.write(rendered)
PY
  echo "rendered ${name}"
done

cat <<EOF

Rendered manifests in k8s/rendered/. Apply with:
  kubectl apply -f k8s/rendered/
EOF
