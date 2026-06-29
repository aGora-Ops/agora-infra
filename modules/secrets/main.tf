
resource "aws_secretsmanager_secret" "service" {
  for_each = toset(var.service_names)

  name        = "stagecraft/${var.environment}/${each.key}"
  description = "Stagecraft ${var.environment} secrets for ${each.key}"

  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = {
    Project     = "stagecraft"
    Environment = var.environment
    Service     = each.key
  }
}

resource "aws_secretsmanager_secret_version" "service" {
  for_each = toset(var.service_names)

  secret_id     = aws_secretsmanager_secret.service[each.key].id
  secret_string = jsonencode(var.secrets[each.key])

  # Terraform writes auto-generated values (DATABASE_URL, SECRET_KEY, SQS_QUEUE_URL,
  # Bedrock agent IDs) on first apply. Manually entered values (GITHUB_CLIENT_ID,
  # GITHUB_CLIENT_SECRET, GITHUB_WEBHOOK_SECRET, FRONTEND_URL) are filled in the
  # AWS Secrets Manager console after first apply and must never be overwritten.
  lifecycle {
    ignore_changes = [secret_string]
  }
}
