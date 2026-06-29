
module "api_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-api"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-api"]
    }
  }

  role_policy_arns = {
    bedrock     = aws_iam_policy.bedrock.arn
    secrets     = aws_iam_policy.secrets_read.arn
    sqs_publish = aws_iam_policy.api_sqs_publish.arn
  }
}

resource "aws_iam_policy" "api_sqs_publish" {
  name = "${var.cluster_name}-api-sqs-publish"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
      Resource = "arn:aws:sqs:${var.aws_region}:${var.account_id}:stagecraft-*"
    }]
  })
}

module "webhook_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-webhook"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-webhook"]
    }
  }
}

module "worker_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-stagecraft-worker"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.kubernetes_namespace}:stagecraft-worker"]
    }
  }

  role_policy_arns = {
    bedrock = aws_iam_policy.bedrock.arn
    ses     = aws_iam_policy.ses_send.arn
  }
}

module "external_secrets_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-external-secrets"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets_read = aws_iam_policy.secrets_read.arn
  }
}

module "cloudwatch_observability_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name = "${var.cluster_name}-cloudwatch-observability"

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:cloudwatch-agent"]
    }
  }

  role_policy_arns = {
    cloudwatch_agent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
}

resource "aws_iam_policy" "bedrock" {
  name = "${var.cluster_name}-bedrock-invoke"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = var.bedrock_model_arn
      },
      {
        # Knowledge Base retrieve + sync (worker ingests docs, API retrieves).
        Effect   = "Allow"
        Action   = ["bedrock:Retrieve", "bedrock:RetrieveAndGenerate"]
        Resource = "arn:aws:bedrock:${var.aws_region}:${var.account_id}:knowledge-base/*"
      },
      {
        # Worker syncs remediation docs to the KB S3 data source.
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::*-kb-data-${var.account_id}/*"
      },
      {
        # Allows assuming the cross-account Bedrock role in the Bedrock account.
        # The role ARN is supplied at runtime via BEDROCK_CROSS_ACCOUNT_ROLE_ARN.
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = "arn:aws:iam::*:role/*bedrock*"
      }
    ]
  })
}

resource "aws_iam_policy" "ses_send" {
  name = "${var.cluster_name}-ses-send"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      # "AI suggested a fix" notification email — SES doesn't support
      # resource-level ARN scoping to a single sender identity for SendEmail
      # (the verified-identity check happens at send time, not via this
      # policy), so this grants the action account-wide rather than to a
      # specific From address.
      Effect   = "Allow"
      Action   = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_policy" "secrets_read" {
  name = "${var.cluster_name}-secrets-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:stagecraft/*"
    }]
  })
}
