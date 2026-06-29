variable "argocd_repo_pat" {
  description = "GitHub PAT with read access to stagecraft-helm (used by ArgoCD to pull chart updates)"
  type        = string
  sensitive   = true
}

variable "enable_karpenter" {
  description = "Install the Karpenter Helm release + NodePool/EC2NodeClass. Requires enable_karpenter = true in the main infra layer (its IAM outputs would otherwise be null)."
  type        = bool
  default     = false
}

variable "tfstate_bucket" {
  description = "S3 bucket holding the main infra layer's Terraform state, read here via data.terraform_remote_state. Must match the bucket in ../backend.tf — unlike a literal backend block, this data source CAN take a variable, so it's parameterized for portability to a different AWS account."
  type        = string
  default     = "stagecraft-tfstate-personal-591316257673"
}

variable "domain_name" {
  description = "Root domain name (must match var.domain_name in ../dev, e.g. ustbiteshub.online). Used to build argocd.<domain>/grafana.<domain> HTTPRoute hostnames. Leave empty to skip both routes entirely (ArgoCD/Grafana stay reachable only via kubectl port-forward)."
  type        = string
  default     = ""
}
