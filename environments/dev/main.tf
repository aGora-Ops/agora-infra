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
#   dns.tf         Route53 zone data source (optional, when hosted_zone_id set)
#   security.tf    WAFv2 Web ACL (REGIONAL), GuardDuty, GuardDuty->SNS
#   cdn.tf         CloudFront + WAFv2 Web ACL (CLOUDFRONT scope), optional
#   monitoring.tf  CloudWatch alarms + dashboard
#   cloudtrail.tf  Multi-region CloudTrail + S3 bucket + CloudWatch Logs
#
# Bedrock agents are NOT created here — they live in the Bedrock AWS account.
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
