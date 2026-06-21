# ── IAM / IRSA ───────────────────────────────────────────────────────
# Per-service IRSA roles (api / webhook / worker / external-secrets /
# cloudwatch-observability) plus the Bedrock invoke + cross-account policy.

module "iam" {
  source = "../../modules/iam"

  cluster_name         = local.name
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider
  aws_region           = var.aws_region
  account_id           = data.aws_caller_identity.current.account_id
  kubernetes_namespace = "agora"
  bedrock_model_arn    = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
}
