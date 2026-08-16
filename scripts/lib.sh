#!/usr/bin/env bash
# Shared helpers sourced by the other scripts in this directory. Not meant to be run
# directly.

set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

REPO_ROOT="$(repo_root)"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

require_cmd() {
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "error: '$cmd' is required but not on PATH" >&2
      exit 1
    fi
  done
}

tf_output() {
  terraform -chdir="${TERRAFORM_DIR}" output -raw "$1"
}
