output "aws_region" {
  value = var.aws_region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "orchestrator_role_arn" {
  description = "Consumed by scripts/render_manifests.sh to annotate the orchestrator ServiceAccount."
  value       = aws_iam_role.orchestrator.arn
}

output "agent_namespace" {
  value = var.agent_namespace
}

output "orchestrator_service_account_name" {
  value = var.orchestrator_service_account_name
}

output "bedrock_inference_profile_id" {
  value = var.bedrock_inference_profile_id
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}
