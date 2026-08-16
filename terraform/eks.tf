# Replaces the spec's `eksctl create cluster` + `eksctl utils
# associate-iam-oidc-provider` with the equivalent Terraform module so the whole
# stack (VPC, cluster, node group, OIDC provider, ECR, IRSA role) lives in one state
# file and comes down with one `terraform destroy`. See README "Deviations from
# spec" for the full eksctl -> Terraform command mapping.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets # control plane ENIs; spans both AZs, required by AWS

  # Modern access-entry based auth instead of the legacy aws-auth ConfigMap, and grant
  # the applying identity admin access so `aws eks update-kubeconfig` + kubectl work
  # immediately after apply.
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true

  # Creates the OIDC provider this cluster's IRSA roles trust - the Terraform
  # equivalent of `eksctl utils associate-iam-oidc-provider`.
  enable_irsa = true

  endpoint_public_access = true # demo cluster; curl/kubectl from a laptop, no VPN

  # The module does not install any addons by default. vpc-cni is created ahead of
  # the node group (before_compute) because kubelet reports NotReady - and EKS marks
  # the whole node group CREATE_FAILED - until a CNI plugin is present on the node.
  addons = {
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
    kube-proxy = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    demo = {
      # Pinned to one AZ's private subnet: EKS requires the *control plane* subnets
      # above to span 2 AZs, but nothing requires the worker nodes to. This is where
      # the spec's "single AZ" actually applies.
      subnet_ids = [module.vpc.private_subnets[var.node_az_index]]

      instance_types = [var.node_instance_type]
      min_size       = var.node_desired_size
      max_size       = var.node_desired_size
      desired_size   = var.node_desired_size
    }
  }
}
