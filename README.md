# EKS Bedrock Troubleshooting Agent

A natural-language Kubernetes troubleshooting assistant for a single EKS cluster,
built as two workloads holding two separate identities that never meet: an
orchestrator (AWS/Bedrock identity, no Kubernetes access) and an executor
(Kubernetes identity, no AWS access). See `architecture.excalidraw` (open at
[excalidraw.com](https://excalidraw.com)) for the full request-flow diagram.

## Prerequisites

- AWS CLI v2, configured with credentials that can create IAM/EKS/ECR/VPC resources
- Terraform >= 1.7
- `kubectl`
- Docker with `buildx` (for `linux/amd64` builds - matters if you're on Apple Silicon)
- `python3` (used by the render script instead of requiring `envsubst`)

## Step-by-step

### 0. Enable Bedrock model access

This is a one-time, per-account, console-only step - there is no Terraform resource
or reliable CLI call for it.

1. AWS Console -> Amazon Bedrock -> **Model access** -> request/enable access for
   **Anthropic Claude Haiku**.
2. **Verify the exact model ID before building anything** - do not assume it, model
   IDs change between releases. At the time this repo was built:

   ```
   aws bedrock get-foundation-model --region us-east-1 \
     --model-identifier anthropic.claude-haiku-4-5-20251001-v1:0 \
     --query "modelDetails.inferenceTypesSupported"
   # -> ["INFERENCE_PROFILE"]
   ```

   That result matters: Claude Haiku 4.5 does **not** support direct on-demand
   `InvokeModel` on the bare foundation-model ARN, only invocation through a
   cross-region **inference profile**. Confirm the profile ID and which regions it
   routes to:

   ```
   aws bedrock list-inference-profiles --region us-east-1 \
     --query "inferenceProfileSummaries[?contains(inferenceProfileId,'haiku')]"
   ```

   `terraform/variables.tf` defaults to `bedrock_base_model_id =
   anthropic.claude-haiku-4-5-20251001-v1:0` and `bedrock_inference_profile_id =
   us.anthropic.claude-haiku-4-5-20251001-v1:0`. Re-run the two commands above and
   update those defaults (or pass `-var`) if either has changed since.

3. Smoke-test access once it's granted:

   ```
   aws bedrock-runtime converse --region us-east-1 \
     --model-id us.anthropic.claude-haiku-4-5-20251001-v1:0 \
     --messages '[{"role":"user","content":[{"text":"reply with OK"}]}]'
   ```

### 1. Provision infrastructure

```
cd terraform
terraform init
terraform apply
```

Creates: a 2-AZ VPC, the EKS cluster and a single-AZ managed node group
(2x `t3.medium`), the OIDC provider, one ECR repository, and the orchestrator's
IRSA role scoped to `bedrock:InvokeModel` on the Haiku inference profile ARN + its
underlying regional foundation-model ARNs only.

```
aws eks update-kubeconfig --region "$(terraform -chdir=terraform output -raw aws_region)" \
  --name "$(terraform -chdir=terraform output -raw cluster_name)"
kubectl get nodes
```

### 2. Build and push the images

```
./scripts/build_and_push.sh          # tags with the current git short SHA
```

### 3. Render and apply the Kubernetes manifests

```
./scripts/render_manifests.sh <the-tag-build_and_push.sh-printed>
kubectl apply -f k8s/rendered/
kubectl -n agent get pods -w
```

`k8s/*.yaml` are templates (`${ORCHESTRATOR_IMAGE}`, `${ORCHESTRATOR_ROLE_ARN}`,
etc.) - always apply from `k8s/rendered/`, not `k8s/` directly.

### 4. Verify end to end

```
kubectl auth can-i get secrets \
  --as=system:serviceaccount:agent:executor --all-namespaces   # expect: no

./scripts/verify.sh
```

`verify.sh` port-forwards the orchestrator locally and runs all five demo questions
(payments, checkout, catalog, kube-system, and the Secret-read denial), printing each
response for you to read against the acceptance criteria below.

### Acceptance criteria

- [ ] `payments` question correctly identifies ImagePullBackOff and the bad image tag
- [ ] `checkout` question correctly identifies the missing Secret reference, diagnosed
      from events alone
- [ ] `catalog` question reports healthy, no false positives
- [ ] `kube-system` question reads it successfully and reports healthy
- [ ] Secret-read question returns a clean "not permitted" message, with a 403 visible
      in `kubectl -n agent logs deploy/executor`
- [ ] `kubectl auth can-i get secrets --as=system:serviceaccount:agent:executor` returns `no`
- [ ] `kubectl exec` into the orchestrator: no static AWS keys in `env`; projected
      token file present at `$AWS_WEB_IDENTITY_TOKEN_FILE`
- [ ] `kubectl exec` into the executor: nothing AWS-related in `env` at all
- [ ] `kubectl -n agent logs deploy/orchestrator` shows each Bedrock tool intent and
      the allowlist validation outcome

## Cost and teardown

Rough running cost while the cluster is up: EKS control plane (~$0.10/hr) + 2x
`t3.medium` (~$0.08/hr) + 1 NAT gateway (~$0.045/hr) ~= **~$0.23/hr, roughly $5-6 for
a 24hr day**. Bedrock bills per token on invocation only. Tear down between sessions:

```
./scripts/teardown.sh
```

This runs `terraform destroy`, which removes the cluster, node group, VPC, ECR repo
(images and all - the repo has `force_delete = true`), and the orchestrator's IAM
role together. Nothing survives that needs a separate manual delete step.
