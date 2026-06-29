variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "stagecraft-dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "domain_name" {
  description = "Root domain name (e.g. stagecraft.example.com)"
  type        = string
  default     = ""
}

variable "github_client_id" {
  description = "GitHub OAuth App client ID — leave empty, fill in AWS Secrets Manager manually after apply"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_client_secret" {
  description = "GitHub OAuth App client secret — leave empty, fill in AWS Secrets Manager manually after apply"
  type        = string
  sensitive   = true
  default     = ""
}

variable "github_webhook_secret" {
  description = "Shared secret for verifying GitHub webhook HMAC — leave empty, fill in AWS Secrets Manager manually after apply"
  type        = string
  sensitive   = true
  default     = ""
}

variable "frontend_url" {
  description = "NLB hostname for the frontend — set after first deploy once the NLB URL is known"
  type        = string
  default     = ""
}

variable "alert_email" {
  description = "Email address for operational notifications"
  type        = string
  default     = ""
}

variable "owns_account_security_baseline" {
  description = "Whether THIS environment's root module owns the account-wide Config singletons. Exactly one of dev/prod should ever be true at a time."
  type        = bool
  default     = true
}

variable "enable_karpenter" {
  description = "Create Karpenter's IAM (controller IRSA role, node role/instance profile, SQS interruption queue). The Helm release + NodePool/EC2NodeClass are applied separately in the platform layer. Existing eks_managed_node_groups are untouched either way — Karpenter only supplements them."
  type        = bool
  default     = false
}
