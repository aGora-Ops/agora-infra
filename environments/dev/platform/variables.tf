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
