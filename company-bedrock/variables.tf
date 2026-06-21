variable "aws_region" {
  description = "AWS region for the Bedrock agents"
  type        = string
  default     = "us-east-1"
}

variable "account_id" {
  description = "Company AWS account ID that owns the Bedrock agents — pass via -var, never commit"
  type        = string
}

variable "assume_role_arn" {
  description = "Optional role to assume in the company account before creating resources — leave empty to use the ambient credentials directly"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Prefix used for agent/role naming"
  type        = string
  default     = "agora"
}

variable "environment" {
  description = "Environment tag for the agents"
  type        = string
  default     = "company"
}
