# ── Compute (EKS) ────────────────────────────────────────────────────
# EKS cluster (private endpoint), prod-sized node groups, core add-ons,
# and the EBS CSI IRSA role.

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
    # enableNetworkPolicy — see environments/dev/compute.tf for the full
    # rationale (NetworkPolicy objects in agora-helm were advisory-only
    # without this; confirmed via the live aws-eks-nodeagent args).
    vpc-cni = {
      most_recent = true
      configuration_values = jsonencode({
        enableNetworkPolicy = "true"
      })
    }
  }

  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

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

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  service_account_role_arn = module.iam.cloudwatch_observability_role_arn

  depends_on = [module.eks, module.iam]
}

# Container Insights (the addon above) writes to these fixed-name log groups.
# Pre-creating them gives us retention + tags instead of the addon's
# auto-created default (never expire, no Owner/Environment tags).
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = toset(["application", "dataplane", "host", "performance"])

  name              = "/aws/containerinsights/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
}
