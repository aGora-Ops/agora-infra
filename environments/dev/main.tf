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

resource "random_password" "db_password" {
  length  = 32
  special = false
}

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
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = local.name
  cluster_version = var.kubernetes_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    app = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 4
      desired_size   = 2
      labels         = { role = "app" }
    }
    worker = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 3
      desired_size   = 1
      labels         = { role = "worker" }
    }
  }

  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_irsa = true

  access_entries = {
    admin = {
      principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/clouduser-iam1"
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "${local.name}-postgres"

  engine         = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  db_name  = "agora"
  username = "agora"
  password = random_password.db_password.result

  allocated_storage = 20
  storage_type      = "gp2"

  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [module.eks.node_security_group_id]

  skip_final_snapshot        = false
  backup_retention_period    = 1
  auto_minor_version_upgrade = true
  publicly_accessible        = false
}

module "ecr" {
  source  = "terraform-aws-modules/ecr/aws"
  version = "~> 2.2"

  for_each = toset(["agora-api", "agora-webhook", "agora-worker", "agora-frontend", "agora-mcp-aws", "agora-mcp-github"])

  repository_name                 = each.key
  repository_image_tag_mutability = "IMMUTABLE"

  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

module "iam" {
  source = "../../modules/iam"

  cluster_name         = local.name
  oidc_provider_arn    = module.eks.oidc_provider_arn
  oidc_provider_url    = module.eks.oidc_provider
  aws_region           = var.aws_region
  account_id           = data.aws_caller_identity.current.account_id
  kubernetes_namespace = "agora"
  bedrock_model_arn    = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
}

# Bedrock agents live in the company AWS account — not created here.
# The worker assumes BEDROCK_CROSS_ACCOUNT_ROLE_ARN to call them cross-account.
# Agent IDs are stored manually in agora/dev/worker Secrets Manager.

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_irsa.iam_role_arn

  depends_on = [module.eks, module.ebs_csi_irsa]
}

resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "amazon-cloudwatch-observability"
  service_account_role_arn = module.iam.cloudwatch_observability_role_arn

  depends_on = [module.eks, module.iam]
}

resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

module "sqs" {
  source = "../../modules/sqs"

  name               = "agora-webhooks"
  environment        = local.env
  max_receive_count  = 3
  sender_role_arn    = module.iam.webhook_role_arn
  consumer_role_arn  = module.iam.worker_role_arn
  alarm_sns_topic_arn = aws_sns_topic.alerts.arn
}

resource "aws_iam_policy" "sqs_send" {
  name = "${local.name}-sqs-send"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      Resource = module.sqs.queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "webhook_sqs_send" {
  role       = module.iam.webhook_role_name
  policy_arn = aws_iam_policy.sqs_send.arn
}

resource "aws_iam_policy" "sqs_consume" {
  name = "${local.name}-sqs-consume"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
      Resource = module.sqs.queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "worker_sqs_consume" {
  role       = module.iam.worker_role_name
  policy_arn = aws_iam_policy.sqs_consume.arn
}

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

module "secrets" {
  source         = "../../modules/secrets"
  environment    = local.env
  service_names  = ["api", "webhook", "worker", "frontend"]

  secrets = {
    api = {
      DATABASE_URL           = "postgresql+asyncpg://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL               = "redis://redis.agora.svc.cluster.local:6379/0"
      GITHUB_CLIENT_ID        = var.github_client_id
      GITHUB_CLIENT_SECRET    = var.github_client_secret
      GITHUB_WEBHOOK_SECRET   = var.github_webhook_secret
      GITHUB_REDIRECT_URI     = "${var.frontend_url}/api/auth/callback"
      FRONTEND_URL            = var.frontend_url
      SQS_QUEUE_URL           = module.sqs.queue_url
      SECRET_KEY              = random_password.secret_key.result
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL  = "postgresql://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL     = "redis://redis.agora.svc.cluster.local:6379/0"
      SQS_QUEUE_URL = module.sqs.queue_url
      SECRET_KEY    = random_password.secret_key.result
      USE_MULTI_AGENT = "true"
      # Fill these manually in AWS Secrets Manager after first apply.
      # They are permanent (survive company account cleanup) so only need setting once.
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN     = ""
      BEDROCK_AGENT_ID_CLASSIFIER        = ""
      BEDROCK_AGENT_ID_ROOT_CAUSE        = ""
      BEDROCK_AGENT_ID_YAML_FIXER        = ""
      BEDROCK_AGENT_ID_SECURITY_REVIEWER = ""
      BEDROCK_AGENT_ID_PR_WRITER         = ""
      BEDROCK_AGENT_ALIAS_ID_CLASSIFIER        = ""
      BEDROCK_AGENT_ALIAS_ID_ROOT_CAUSE        = ""
      BEDROCK_AGENT_ALIAS_ID_YAML_FIXER        = ""
      BEDROCK_AGENT_ALIAS_ID_SECURITY_REVIEWER = ""
      BEDROCK_AGENT_ALIAS_ID_PR_WRITER         = ""
    }
    frontend = {
      NEXTAUTH_SECRET       = random_password.secret_key.result
      GITHUB_CLIENT_ID      = var.github_client_id
      GITHUB_CLIENT_SECRET  = var.github_client_secret
    }
  }
}

# Bedrock VPC endpoints removed — worker calls Bedrock cross-account via
# sts:AssumeRole into the company account, so same-account VPC endpoints
# don't apply. Cross-account traffic routes over the public Bedrock endpoint.

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.3"

  count = var.domain_name != "" ? 1 : 0

  domain_name = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]

  create_route53_records = true
  validation_method       = "DNS"
  wait_for_validation      = true
}

resource "aws_wafv2_web_acl" "main" {
  name  = "${local.name}-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${local.name}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "RDS CPU above 80% for 15 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  alarm_name          = "${local.name}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "RDS free storage below 2 GiB"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.postgres.identifier
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}


resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title   = "RDS CPU & Connections"
          region  = var.aws_region
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.postgres.identifier],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.postgres.identifier],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title   = "SQS Queue Depth (main + DLQ)"
          region  = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "agora-webhooks"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "agora-webhooks-dlq"],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title   = "EKS Cluster CPU & Memory (Container Insights)"
          region  = var.aws_region
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", local.name],
            ["ContainerInsights", "node_memory_utilization", "ClusterName", local.name],
          ]
        }
      },
    ]
  })
}

