variable "argocd_repo_pat" {
  description = "GitHub PAT with read access to agora-helm (used by ArgoCD to pull chart updates)"
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
  default     = "agora-tfstate-personal-591316257673"
}
