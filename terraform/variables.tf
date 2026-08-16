variable "aws_region" {
  description = <<-EOT
    Region for every resource in this stack, including the Bedrock inference profile.
    Must be one of the regions the "us." cross-region inference profile for Claude
    Haiku actually routes to (us-east-1, us-east-2, us-west-2) or InvokeModel calls
    will fail. us-east-1 has the broadest Bedrock feature availability.
  EOT
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "bedrock-troubleshooting-agent"
}

variable "cluster_version" {
  description = <<-EOT
    Kubernetes version for the EKS control plane. Verify this is still within
    standard support before applying: `aws eks describe-cluster-versions --query
    "clusterVersions[?status=='STANDARD_SUPPORT'].clusterVersion"`.
  EOT
  type        = string
  default     = "1.34"
}

variable "node_instance_type" {
  description = "Instance type for the single managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Number of worker nodes. The spec calls for 2."
  type        = number
  default     = 2
}

variable "node_az_index" {
  description = <<-EOT
    Index into the VPC's private subnets that the (single-AZ) managed node group is
    pinned to. EKS itself requires control-plane subnets across at least 2 AZs -
    that requirement is independent of this and cannot be relaxed - but nothing
    requires the *worker nodes* to spread across more than one of them, so this
    picks one AZ for the node group only.
  EOT
  type        = number
  default     = 0
}

variable "vpc_cidr" {
  description = "CIDR block for the demo VPC."
  type        = string
  default     = "10.42.0.0/16"
}

# --- Bedrock ---
#
# Claude Haiku 4.5 (checked live via `aws bedrock get-foundation-model` at build time)
# only supports INFERENCE_PROFILE invocation, not direct on-demand InvokeModel on the
# bare foundation-model ARN. IAM must therefore grant bedrock:InvokeModel on the
# inference profile ARN *and* the regional foundation-model ARNs it can route to -
# granting only the profile ARN is not sufficient; Bedrock checks both. Re-verify with
# `aws bedrock list-inference-profiles` before relying on this default, since model
# IDs and profile routing are Anthropic/AWS's to change.

variable "bedrock_base_model_id" {
  description = "Underlying Anthropic foundation model ID backing the inference profile."
  type        = string
  default     = "anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "bedrock_inference_profile_id" {
  description = "Cross-region inference profile ID used for the actual Converse/InvokeModel calls."
  type        = string
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "bedrock_profile_regions" {
  description = "Regions the inference profile above is allowed to route inference to."
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-2"]
}

# --- App identities ---

variable "agent_namespace" {
  description = "Kubernetes namespace the orchestrator and executor run in."
  type        = string
  default     = "agent"
}

variable "orchestrator_service_account_name" {
  description = "Name of the orchestrator's Kubernetes ServiceAccount (the IRSA trust policy is scoped to this exact name + namespace)."
  type        = string
  default     = "orchestrator"
}

variable "ecr_repository_name" {
  description = "Single ECR repository holding both images, distinguished by tag."
  type        = string
  default     = "eks-bedrock-troubleshooting-agent"
}
