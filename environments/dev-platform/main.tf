data "aws_caller_identity" "current" {}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = var.tfstate_bucket
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "kubernetes" {
  host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.cluster_name, "--region", "us-east-1"]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.infra.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infra.outputs.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infra.outputs.cluster_name, "--region", "us-east-1"]
    }
  }
}

resource "kubernetes_namespace" "agora" {
  metadata {
    name = "agora"
  }
}

resource "kubernetes_deployment" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.agora.metadata[0].name
    labels    = { app = "redis" }
  }

  spec {
    replicas = 1
    selector {
      match_labels = { app = "redis" }
    }
    template {
      metadata {
        labels = { app = "redis" }
      }
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          port {
            container_port = 6379
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "redis"
    namespace = kubernetes_namespace.agora.metadata[0].name
  }
  spec {
    selector = { app = "redis" }
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

resource "terraform_data" "gateway_api_crds" {
  provisioner "local-exec" {
    command    = "kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml"
    on_failure = continue
  }
}

resource "helm_release" "kgateway_crds" {
  name             = "kgateway-crds"
  repository       = "oci://cr.kgateway.dev/kgateway-dev/charts"
  chart            = "kgateway-crds"
  version          = "v2.3.1"
  namespace        = "kgateway-system"
  create_namespace = true

  set {
    name  = "controller.image.pullPolicy"
    value = "Always"
  }

  depends_on = [terraform_data.gateway_api_crds]
}

resource "helm_release" "kgateway" {
  name       = "kgateway"
  repository = "oci://cr.kgateway.dev/kgateway-dev/charts"
  chart      = "kgateway"
  version    = "v2.3.1"
  namespace  = "kgateway-system"

  set {
    name  = "controller.image.pullPolicy"
    value = "Always"
  }

  depends_on = [helm_release.kgateway_crds]
}

resource "kubernetes_manifest" "gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "agora-gateway"
      namespace = "kgateway-system"
    }
    spec = {
      gatewayClassName = "kgateway"
      listeners = [
        {
          name          = "http"
          protocol      = "HTTP"
          port          = 80
          allowedRoutes = { namespaces = { from = "All" } }
        },
      ]
    }
  }

  depends_on = [helm_release.kgateway]
}

resource "kubernetes_manifest" "reference_grant" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-agora-routes"
      namespace = "kgateway-system"
    }
    spec = {
      from = [
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = "agora"
        },
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = "argocd"
        },
        {
          group     = "gateway.networking.k8s.io"
          kind      = "HTTPRoute"
          namespace = "monitoring"
        },
      ]
      to = [{
        group = "gateway.networking.k8s.io"
        kind  = "Gateway"
      }]
    }
  }

  depends_on = [kubernetes_manifest.gateway]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.10.4"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.infra.outputs.external_secrets_role_arn
  }
}

resource "kubernetes_manifest" "cluster_secret_store" {
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata   = { name = "aws-secretsmanager" }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = "us-east-1"
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = "external-secrets"
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.external_secrets]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.6.12"

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }
}

resource "kubernetes_manifest" "argocd_httproute" {
  count = var.domain_name != "" ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "argocd-server"
      namespace = "argocd"
    }
    spec = {
      parentRefs = [{
        group     = "gateway.networking.k8s.io"
        kind      = "Gateway"
        name      = "agora-gateway"
        namespace = "kgateway-system"
      }]
      hostnames = ["argocd.${var.domain_name}"]
      rules = [{
        matches = [{ path = { type = "PathPrefix", value = "/" } }]
        backendRefs = [{
          group = ""
          kind  = "Service"
          name  = "argocd-server"
          port  = 80
        }]
      }]
    }
  }

  depends_on = [helm_release.argocd, kubernetes_manifest.reference_grant]
}

resource "kubernetes_secret" "argocd_repo_helm" {
  metadata {
    name      = "agora-helm-repo"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = "https://github.com/aGora-Ops/agora-helm.git"
    username = "x-access-token"
    password = var.argocd_repo_pat
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "argocd_app" {
  for_each = toset(["agora-api", "agora-webhook", "agora-worker", "agora-frontend", "agora-mcp-github"])

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = each.key
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/aGora-Ops/agora-helm.git"
        targetRevision = "main"
        path           = "charts/${each.key}"
        helm = {
          valueFiles = ["values.yaml", "values.dev.yaml"]
          parameters = [
            { name = "aws.mainAccountId", value = data.aws_caller_identity.current.account_id },
            { name = "aws.clusterName", value = data.terraform_remote_state.infra.outputs.cluster_name },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "agora"
      }
      syncPolicy = {
        automated   = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_secret.argocd_repo_helm]
}

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = "1.0.6"
  namespace        = "karpenter"
  create_namespace = true

  set {
    name  = "settings.clusterName"
    value = data.terraform_remote_state.infra.outputs.cluster_name
  }

  set {
    name  = "settings.interruptionQueue"
    value = data.terraform_remote_state.infra.outputs.karpenter_interruption_queue_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = data.terraform_remote_state.infra.outputs.karpenter_controller_role_arn
  }
}

resource "kubernetes_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata   = { name = "default" }
    spec = {
      role = data.terraform_remote_state.infra.outputs.karpenter_node_role_name
      amiSelectorTerms = [
        { alias = "al2023@latest" }
      ]
      subnetSelectorTerms = [
        { tags = { "kubernetes.io/role/internal-elb" = "1" } }
      ]
      securityGroupSelectorTerms = [
        { id = data.terraform_remote_state.infra.outputs.node_security_group_id }
      ]
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_node_pool" {
  count = var.enable_karpenter ? 1 : 0

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata   = { name = "default" }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }
          requirements = [
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "node.kubernetes.io/instance-type", operator = "In", values = ["t3.medium", "t3.large"] },
          ]
        }
      }
      limits = { cpu = "8" }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "5m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_node_class]
}

resource "kubernetes_manifest" "argocd_app_monitoring" {
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "monitoring"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://prometheus-community.github.io/helm-charts"
        chart          = "kube-prometheus-stack"
        targetRevision = "65.5.1"
        helm = {
          skipCrds = true
          values = yamlencode({
            grafana = {
              service = { type = "ClusterIP" }
              resources = {
                requests = { cpu = "50m", memory = "128Mi" }
                limits   = { cpu = "200m", memory = "256Mi" }
              }
            }
            prometheus = {
              prometheusSpec = {
                resources = {
                  requests = { cpu = "100m", memory = "512Mi" }
                  limits   = { cpu = "500m", memory = "1Gi" }
                }
                retention = "7d"
              }
            }
            alertmanager = { enabled = false }
          })
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "monitoring"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true", "ServerSideApply=true"]
      }
    }
  }

  depends_on = [helm_release.argocd]
}

resource "kubernetes_manifest" "grafana_httproute" {
  count = var.domain_name != "" ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "grafana"
      namespace = "monitoring"
    }
    spec = {
      parentRefs = [{
        group     = "gateway.networking.k8s.io"
        kind      = "Gateway"
        name      = "agora-gateway"
        namespace = "kgateway-system"
      }]
      hostnames = ["grafana.${var.domain_name}"]
      rules = [{
        matches = [{ path = { type = "PathPrefix", value = "/" } }]
        backendRefs = [{
          group = ""
          kind  = "Service"
          name  = "monitoring-grafana"
          port  = 80
        }]
      }]
    }
  }

  depends_on = [kubernetes_manifest.argocd_app_monitoring]
}
