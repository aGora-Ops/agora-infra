variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "agora-prod"
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
  description = "Root domain name (e.g. agora.example.com)"
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
  default     = "https://agora.example.com"
}

variable "alert_email" {
  description = "Email address to receive CloudWatch alarm notifications (DLQ depth, etc.)"
  type        = string
}

variable "log_retention_days" {
  description = "Retention period (days) for CloudWatch log groups (EKS control plane, Container Insights)"
  type        = number
  default     = 30
}

