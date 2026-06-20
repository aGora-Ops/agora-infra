data "aws_caller_identity" "current" {}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "agora-terraform-state-353284253443"
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

resource "helm_release" "kgateway_crds" {
  name             = "kgateway-crds"
  repository       = "oci://ghcr.io/kgateway-dev/charts"
  chart            = "kgateway-crds"
  version          = "v2.3.4"
  namespace        = "kgateway-system"
  create_namespace = true
}

resource "helm_release" "kgateway" {
  name       = "kgateway"
  repository = "oci://ghcr.io/kgateway-dev/charts"
  chart      = "kgateway"
  version    = "2.0.1"
  namespace  = "kgateway-system"

  depends_on = [helm_release.kgateway_crds]
}

resource "kubernetes_manifest" "gateway_class" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata   = { name = "kgateway" }
    spec       = { controllerName = "kgateway.io/kgateway" }
  }

  depends_on = [helm_release.kgateway]
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
          name     = "http"
          protocol = "HTTP"
          port     = 80
        },
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              name      = "agora-tls"
              namespace = "kgateway-system"
            }]
          }
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway_class]
}

# Allows HTTPRoutes in the agora namespace to reference the Gateway in kgateway-system
resource "kubernetes_manifest" "reference_grant" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1beta1"
    kind       = "ReferenceGrant"
    metadata = {
      name      = "allow-agora-routes"
      namespace = "kgateway-system"
    }
    spec = {
      from = [{
        group     = "gateway.networking.k8s.io"
        kind      = "HTTPRoute"
        namespace = "agora"
      }]
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
  for_each = toset(["agora-api", "agora-webhook", "agora-worker", "agora-frontend", "agora-mcp-aws", "agora-mcp-github"])

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
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "agora"
      }
      syncPolicy = {
        automated = { prune = true, selfHeal = true }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }

  depends_on = [helm_release.argocd, kubernetes_secret.argocd_repo_helm]
}
