resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "random_password" "internal_api_key" {
  length  = 48
  special = false
}

module "secrets" {
  source        = "../../modules/secrets"
  environment   = local.env
  service_names = ["api", "webhook", "worker", "frontend", "mcp-github"]

  secrets = {
    api = {
      DATABASE_URL                   = "postgresql+asyncpg://stagecraft:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/stagecraft"
      REDIS_URL                      = "rediss://:${random_password.redis_auth.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
      GITHUB_CLIENT_ID               = var.github_client_id
      GITHUB_CLIENT_SECRET           = var.github_client_secret
      GITHUB_WEBHOOK_SECRET          = var.github_webhook_secret
      GITHUB_REDIRECT_URI            = "${var.frontend_url}/api/auth/callback"
      FRONTEND_URL                   = var.frontend_url
      SQS_QUEUE_URL                  = module.sqs.queue_url
      SECRET_KEY                     = random_password.secret_key.result
      INTERNAL_API_KEY               = random_password.internal_api_key.result
      WORKER_INTERNAL_URL            = "http://stagecraft-worker-stagecraft-worker.stagecraft.svc.cluster.local:8080"
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN = ""
      BEDROCK_GUARDRAIL_ID           = aws_bedrock_guardrail.main.guardrail_id
      BEDROCK_GUARDRAIL_VERSION      = aws_bedrock_guardrail_version.main.version
      BEDROCK_KB_ID                  = aws_bedrockagent_knowledge_base.remediations.id
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL                             = "postgresql://stagecraft:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/stagecraft"
      REDIS_URL                                = "rediss://:${random_password.redis_auth.result}@${aws_elasticache_replication_group.redis.primary_endpoint_address}:6379/0"
      SQS_QUEUE_URL                            = module.sqs.queue_url
      SECRET_KEY                               = random_password.secret_key.result
      USE_MULTI_AGENT                          = "true"
      INTERNAL_API_KEY                         = random_password.internal_api_key.result
      FRONTEND_URL                             = var.frontend_url
      SES_ENABLED                              = "false"
      SES_FROM_EMAIL                           = ""
      BEDROCK_KB_ID                            = aws_bedrockagent_knowledge_base.remediations.id
      BEDROCK_KB_S3_BUCKET                     = aws_s3_bucket.kb_data.bucket
      BEDROCK_GUARDRAIL_ID                     = aws_bedrock_guardrail.main.guardrail_id
      BEDROCK_GUARDRAIL_VERSION                = aws_bedrock_guardrail_version.main.version
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN           = ""
      BEDROCK_AGENT_ID_CLASSIFIER              = ""
      BEDROCK_AGENT_ID_ROOT_CAUSE              = ""
      BEDROCK_AGENT_ID_YAML_FIXER              = ""
      BEDROCK_AGENT_ID_SECURITY_REVIEWER       = ""
      BEDROCK_AGENT_ID_PR_WRITER               = ""
      BEDROCK_AGENT_ALIAS_ID_CLASSIFIER        = ""
      BEDROCK_AGENT_ALIAS_ID_ROOT_CAUSE        = ""
      BEDROCK_AGENT_ALIAS_ID_YAML_FIXER        = ""
      BEDROCK_AGENT_ALIAS_ID_SECURITY_REVIEWER = ""
      BEDROCK_AGENT_ALIAS_ID_PR_WRITER         = ""
    }
    frontend = {
      NEXTAUTH_SECRET      = random_password.secret_key.result
      GITHUB_CLIENT_ID     = var.github_client_id
      GITHUB_CLIENT_SECRET = var.github_client_secret
    }
    "mcp-github" = {
      INTERNAL_API_KEY       = random_password.internal_api_key.result
      STAGECRAFT_API_URL          = "http://stagecraft-api-stagecraft-api.stagecraft.svc.cluster.local:8000"
      GITHUB_APP_ID          = ""
      GITHUB_APP_PRIVATE_KEY = ""
      ALLOWED_ORG            = ""
    }
  }
}
