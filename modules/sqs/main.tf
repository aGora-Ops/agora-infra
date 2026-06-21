resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name}-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = "alias/aws/sqs"

  tags = { Name = "${var.name}-dlq", Environment = var.environment }
}

resource "aws_sqs_queue" "main" {
  name                       = var.name
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  kms_master_key_id          = "alias/aws/sqs"

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = var.name, Environment = var.environment }
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "DLQ ${var.name}-dlq has at least one message — a webhook or analysis task is failing repeatedly."
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [var.alarm_sns_topic_arn]
  ok_actions    = [var.alarm_sns_topic_arn]
}

resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSend"
        Effect    = "Allow"
        Principal = { AWS = var.sender_role_arn }
        Action    = ["sqs:SendMessage"]
        Resource  = aws_sqs_queue.main.arn
      },
      {
        Sid       = "AllowConsume"
        Effect    = "Allow"
        Principal = { AWS = var.consumer_role_arn }
        Action    = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource  = aws_sqs_queue.main.arn
      }
    ]
  })
}
