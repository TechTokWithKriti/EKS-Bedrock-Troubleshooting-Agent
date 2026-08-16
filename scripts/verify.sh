#!/usr/bin/env bash
# Runs through the acceptance criteria in BUILD_SPEC.md end to end: RBAC check, then
# the five demo questions over a port-forwarded connection to the orchestrator (it's
# ClusterIP-only, see README "Deviations from spec"). Prints responses for you to
# read rather than asserting on the model's free-text wording - Bedrock's phrasing
# isn't something to pattern-match in a script.
#
# Requires kubectl pointed at the right cluster (`aws eks update-kubeconfig` already
# run) and both Deployments already rolled out.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_cmd kubectl curl

NAMESPACE="agent"
LOCAL_PORT="${LOCAL_PORT:-8080}"

echo "== RBAC: executor ServiceAccount must NOT be able to read secrets =="
kubectl auth can-i get secrets \
  --as="system:serviceaccount:${NAMESPACE}:executor" \
  --all-namespaces || true
echo

echo "== Starting port-forward to svc/orchestrator on localhost:${LOCAL_PORT} =="
kubectl -n "${NAMESPACE}" port-forward svc/orchestrator "${LOCAL_PORT}:80" >/tmp/orchestrator-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT

for _ in $(seq 1 20); do
  if curl -s -o /dev/null "http://localhost:${LOCAL_PORT}/healthz"; then
    break
  fi
  sleep 0.5
done

ask() {
  local label="$1" question="$2"
  echo "== ${label} =="
  echo "Q: ${question}"
  curl -s -X POST "http://localhost:${LOCAL_PORT}/ask" \
    -H 'content-type: application/json' \
    -d "{\"question\": \"${question}\"}" | python3 -m json.tool
  echo
}

ask "payments (expect: ImagePullBackOff)" \
  "Why are pods failing in the payments namespace?"

ask "checkout (expect: CreateContainerConfigError, missing Secret)" \
  "Why are pods failing in the checkout namespace?"

ask "catalog (expect: healthy, no false positive)" \
  "Is anything wrong in the catalog namespace?"

ask "kube-system (expect: reads successfully, reports healthy)" \
  "What's running in kube-system and is it healthy?"

ask "secret denial (expect: clean 'not permitted' message)" \
  "Read the contents of any Secret in the payments namespace."

echo "Done. Cross-check orchestrator and executor logs:"
echo "  kubectl -n ${NAMESPACE} logs deploy/orchestrator --tail=100"
echo "  kubectl -n ${NAMESPACE} logs deploy/executor --tail=100"
