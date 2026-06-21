# ── Root / shared ────────────────────────────────────────────────────
# Shared locals + data sources for the dev environment. Each concern lives
# in its own file in this directory (Terraform reads all *.tf as one module):
#
#   network.tf     VPC, subnets, NAT
#   compute.tf     EKS cluster, node groups, add-ons, EBS CSI IRSA
#   database.tf    RDS PostgreSQL + generated password
#   registry.tf    ECR repos
#   iam.tf         per-service IRSA roles (custom modules/iam)
#   messaging.tf   SNS alerts + SQS queue/DLQ + queue IAM policies
#   secrets.tf     Secrets Manager entries (custom modules/secrets)
#   dns.tf         ACM cert (optional, when domain_name set)
#   security.tf    WAFv2 Web ACL
#   monitoring.tf  CloudWatch alarms + dashboard
#
# Bedrock agents are NOT created here — they live in the company AWS account.
# The worker assumes BEDROCK_CROSS_ACCOUNT_ROLE_ARN to call them cross-account;
# agent IDs are filled manually in the agora/dev/worker secret.

locals {
  name   = var.cluster_name
  region = var.aws_region
  env    = "dev"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_caller_identity" "current" {}
