# ── Messaging (SQS + SNS) ────────────────────────────────────────────
# SNS alert topic (email), the webhook event queue + DLQ, and the IAM
# policies binding webhook (send) and worker (consume) to the queue.

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

  name                = "agora-webhooks"
  environment         = local.env
  max_receive_count   = 3
  sender_role_arn     = module.iam.webhook_role_arn
  consumer_role_arn   = module.iam.worker_role_arn
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
