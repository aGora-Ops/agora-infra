output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "app_secrets_arns" {
  description = "ARNs of the per-service Secrets Manager entries (agora/dev/*)"
  value       = module.secrets.secret_arns
}

output "sqs_queue_url" {
  description = "SQS queue URL for webhook events"
  value       = module.sqs.queue_url
}

output "ecr_urls" {
  description = "ECR repository URLs"
  value       = { for k, v in module.ecr : k => v.repository_url }
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI Driver"
  value       = module.ebs_csi_irsa.iam_role_arn
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA certificate for the EKS cluster (used by platform layer)"
  value       = module.eks.cluster_certificate_authority_data
}

output "external_secrets_role_arn" {
  description = "IRSA role ARN for External Secrets Operator (used by platform layer)"
  value       = module.iam.external_secrets_role_arn
}

output "waf_web_acl_arn" {
  description = "WAFv2 Web ACL ARN — set as the alb.ingress.kubernetes.io/wafv2-acl-arn annotation on each public Ingress (agora-helm) to actually protect the ALBs"
  value       = aws_wafv2_web_acl.main.arn
}

output "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (used by platform layer for Karpenter IRSA)"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "EKS OIDC provider URL, no https:// prefix (used by platform layer for Karpenter IRSA)"
  value       = module.eks.oidc_provider
}

output "cluster_endpoint_for_karpenter" {
  description = "Same as cluster_endpoint — explicit alias documenting Karpenter's NodeClass needs it"
  value       = module.eks.cluster_endpoint
}

output "node_security_group_id" {
  description = "EKS node security group ID — Karpenter-launched nodes join this group too"
  value       = module.eks.node_security_group_id
}

output "karpenter_controller_role_arn" {
  description = "IRSA role ARN for the Karpenter controller (used by platform layer). Null when enable_karpenter = false."
  value       = var.enable_karpenter ? module.karpenter[0].iam_role_arn : null
}

output "karpenter_node_role_name" {
  description = "IAM role name for Karpenter-launched nodes, referenced by EC2NodeClass. Null when enable_karpenter = false."
  value       = var.enable_karpenter ? module.karpenter[0].node_iam_role_name : null
}

output "karpenter_interruption_queue_name" {
  description = "SQS queue name for Karpenter spot interruption handling. Null when enable_karpenter = false."
  value       = var.enable_karpenter ? module.karpenter[0].queue_name : null
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution's *.cloudfront.net hostname. Null when nlb_hostname is unset."
  value       = var.nlb_hostname != "" ? aws_cloudfront_distribution.main[0].domain_name : null
}

output "cloudfront_waf_web_acl_arn" {
  description = "CLOUDFRONT-scope WAFv2 Web ACL ARN, attached to the CloudFront distribution automatically. Null when nlb_hostname is unset."
  value       = var.nlb_hostname != "" ? aws_wafv2_web_acl.cloudfront[0].arn : null
}
