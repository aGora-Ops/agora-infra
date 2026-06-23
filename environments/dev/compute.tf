# ── Compute (EKS) ────────────────────────────────────────────────────
# EKS cluster, managed node groups, core add-ons, and the EBS CSI IRSA role.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    app = {
      instance_types = ["t3.medium"]
      # Scaled to 0 (2026-06-24) for cost control — control plane fee keeps
      # running either way, this only cuts the EC2 node cost. Restore to
      # min_size=1, desired_size=2 to bring the app back online.
      min_size     = 0
      max_size     = 4
      desired_size = 0
      labels       = { role = "app" }
    }
    worker = {
      instance_types = ["t3.medium"]
      # Same as above — restore to min_size=1, desired_size=1.
      min_size     = 0
      max_size     = 3
      desired_size = 0
      labels       = { role = "worker" }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    # enableNetworkPolicy is required for the NetworkPolicy objects already
    # deployed (agora-helm's charts/*/templates/networkpolicy.yaml) to
    # actually be enforced. Confirmed missing on the live cluster
    # (2026-06-23): `kubectl get daemonset aws-node -n kube-system` showed
    # the addon's network-policy-agent container running, but started with
    # --enable-network-policy=false — every NetworkPolicy in this project
    # has been advisory-only, not restricting any real traffic, until this
    # is applied.
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

  # Allow the ArgoCD NLB (LoadBalancer service, target-type instance,
  # externalTrafficPolicy: Local) to reach the NodePort + kube-proxy
  # healthCheckNodePort on the nodes. Without this the node security group
  # rejects the NLB's health checks and the target group stays unhealthy.
  node_security_group_additional_rules = {
    nlb_health_check = {
      description = "Allow NLB health checks / NodePort traffic for LoadBalancer services"
      protocol    = "tcp"
      from_port   = 30000
      to_port     = 32767
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
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

# ── Karpenter IAM (controller IRSA, node role/instance profile, SQS
# interruption queue + EventBridge rules) ──────────────────────────────
# IAM only — the Helm release and NodePool/EC2NodeClass live in the platform
# layer, which needs the cluster to already exist. Karpenter supplements the
# eks_managed_node_groups above; it does not replace them, and nothing
# currently schedules onto Karpenter-provisioned nodes, so it stays dormant
# until a NodePool actually has unschedulable pods to react to.
module "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.11"

  cluster_name = module.eks.cluster_name

  enable_irsa                     = true
  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]

  # Karpenter-launched nodes use this role; same permission set as the
  # existing managed node groups get automatically from the EKS module.
  create_node_iam_role = true
  node_iam_role_name   = "${local.name}-karpenter-node"

  # IRSA (not Pod Identity) to match the IRSA pattern used everywhere else
  # in this project (api/webhook/worker/external-secrets/cloudwatch roles).
  enable_pod_identity             = false
  create_pod_identity_association = false
}
