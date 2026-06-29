module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    app = {
      instance_types = ["t3.medium"]
      min_size       = 3
      max_size       = 10
      desired_size   = 3
      labels         = { role = "app" }
    }
    worker = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
      labels         = { role = "worker" }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }

  enable_irsa = true
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  depends_on = [module.eks, module.ebs_csi_irsa]
}
