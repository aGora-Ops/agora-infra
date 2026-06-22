# ── Secrets Manager ──────────────────────────────────────────────────
# Per-service secrets (api / webhook / worker / frontend). Auto-generated
# values (DATABASE_URL, SECRET_KEY, SQS_QUEUE_URL) are written by Terraform;
# GitHub OAuth + Bedrock agent fields are left empty and filled manually in
# the console (the module uses ignore_changes so applies never overwrite them).

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

module "secrets" {
  source        = "../../modules/secrets"
  environment   = local.env
  service_names = ["api", "webhook", "worker", "frontend"]

  secrets = {
    api = {
      DATABASE_URL          = "postgresql+asyncpg://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL             = "redis://redis.agora.svc.cluster.local:6379/0"
      GITHUB_CLIENT_ID      = var.github_client_id
      GITHUB_CLIENT_SECRET  = var.github_client_secret
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      GITHUB_REDIRECT_URI   = "${var.frontend_url}/api/auth/callback"
      FRONTEND_URL          = var.frontend_url
      SQS_QUEUE_URL         = module.sqs.queue_url
      SECRET_KEY            = random_password.secret_key.result
      # Pipeline Chat (Feature 3) — assume Bedrock-account Bedrock role.
      # Fill manually in AWS Secrets Manager after first apply.
      BEDROCK_CROSS_ACCOUNT_ROLE_ARN = ""
    }
    webhook = {
      GITHUB_WEBHOOK_SECRET = var.github_webhook_secret
      SQS_QUEUE_URL         = module.sqs.queue_url
    }
    worker = {
      DATABASE_URL    = "postgresql://agora:${random_password.db_password.result}@${aws_db_instance.postgres.address}:${aws_db_instance.postgres.port}/agora"
      REDIS_URL       = "redis://redis.agora.svc.cluster.local:6379/0"
      SQS_QUEUE_URL   = module.sqs.queue_url
      SECRET_KEY      = random_password.secret_key.result
      USE_MULTI_AGENT = "true"
      # Fill these manually in AWS Secrets Manager after first apply.
      # They are permanent (survive Bedrock account cleanup) so only need setting once.
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
  }
}
