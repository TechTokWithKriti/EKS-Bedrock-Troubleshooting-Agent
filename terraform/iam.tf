# IRSA role for the orchestrator only. The executor gets no AWS identity at all - it
# runs on a plain Kubernetes ServiceAccount with no IAM role annotation (see k8s/).

data "aws_caller_identity" "current" {}

locals {
  oidc_issuer_no_scheme = replace(module.eks.cluster_oidc_issuer_url, "https://", "")

  bedrock_inference_profile_arn = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.bedrock_inference_profile_id}"

  bedrock_foundation_model_arns = [
    for region in var.bedrock_profile_regions :
    "arn:aws:bedrock:${region}::foundation-model/${var.bedrock_base_model_id}"
  ]
}

data "aws_iam_policy_document" "orchestrator_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_no_scheme}:sub"
      values   = ["system:serviceaccount:${var.agent_namespace}:${var.orchestrator_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer_no_scheme}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "orchestrator" {
  name               = "${var.cluster_name}-orchestrator-irsa"
  assume_role_policy = data.aws_iam_policy_document.orchestrator_trust.json
}

# Scoped to Bedrock InvokeModel on Claude Haiku only - both the inference profile ARN
# and the regional foundation-model ARNs it routes to are required; granting only one
# or the other produces an AccessDeniedException at call time even though the role
# "looks" correctly scoped in the console.
data "aws_iam_policy_document" "orchestrator_bedrock" {
  statement {
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = concat(
      [local.bedrock_inference_profile_arn],
      local.bedrock_foundation_model_arns,
    )
  }
}

resource "aws_iam_policy" "orchestrator_bedrock" {
  name   = "${var.cluster_name}-orchestrator-bedrock-invoke"
  policy = data.aws_iam_policy_document.orchestrator_bedrock.json
}

resource "aws_iam_role_policy_attachment" "orchestrator_bedrock" {
  role       = aws_iam_role.orchestrator.name
  policy_arn = aws_iam_policy.orchestrator_bedrock.arn
}
