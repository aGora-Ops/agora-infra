variable "cluster_name" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "aws_region" { type = string }
variable "account_id" { type = string }
variable "bedrock_model_arn" { type = string }

variable "kubernetes_namespace" {
  type    = string
  default = "agora"
}
