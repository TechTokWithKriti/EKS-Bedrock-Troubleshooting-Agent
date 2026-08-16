#!/usr/bin/env bash
# Tears down everything in one command: EKS cluster, node group, VPC, ECR repo (with
# force_delete = true, so this works even with images still in it), and the
# orchestrator's IAM role. All of it is in the same Terraform state, so unlike the
# spec's eksctl-based flow there is no separate "delete the ECR repo and IAM role too"
# step - `terraform destroy` is the whole teardown.
#
# Run this only after every recording has been watched back in full - see the Build
# Checklist in README.md.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd terraform

read -r -p "This will destroy the entire ${REPO_ROOT##*/} stack (EKS cluster, VPC, ECR, IAM role). Type 'destroy' to continue: " confirm
if [ "${confirm}" != "destroy" ]; then
  echo "Aborted."
  exit 1
fi

terraform -chdir="${TERRAFORM_DIR}" destroy
