# ── Networking ───────────────────────────────────────────────────────
# VPC with public / private / database subnets across 3 AZs, per-AZ NAT
# (prod HA). Also the Bedrock interface VPC endpoints (see note below).

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs              = local.azs
  private_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets   = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]

  create_database_subnet_group = true

  enable_nat_gateway   = true
  single_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  # VPC Flow Logs — see environments/dev/network.tf for the full rationale
  # (network-plane audit trail, pairs with CloudTrail's control-plane
  # trail). Per-VPC, not an account singleton — both dev and prod get their
  # own, no gating needed.
  enable_flow_log                                 = true
  create_flow_log_cloudwatch_log_group            = true
  create_flow_log_cloudwatch_iam_role             = true
  flow_log_traffic_type                           = "ALL"
  flow_log_max_aggregation_interval               = 600
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days
}

# Bedrock VPC endpoints removed — worker calls Bedrock cross-account via
# sts:AssumeRole into the Bedrock account, so same-account VPC endpoints
# don't apply. Cross-account traffic routes over the public Bedrock endpoint.
