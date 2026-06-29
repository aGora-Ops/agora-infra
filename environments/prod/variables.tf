variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "stagecraft-prod"
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
  description = "Public URL of the frontend (used for OAuth redirects and CORS)"
  type        = string
  default     = "https://stagecraft.example.com"
}

variable "alert_email" {
  description = "Email address for operational notifications"
  type        = string
  default     = ""
}

variable "owns_account_security_baseline" {
  description = "Whether THIS environment's root module owns the account-wide Config singletons. Exactly one of dev/prod should ever be true at a time."
  type        = bool
  default     = false
}
