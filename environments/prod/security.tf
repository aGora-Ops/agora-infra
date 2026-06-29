# ── Security (WAF) ───────────────────────────────────────────────────
# Regional WAFv2 Web ACL with the AWS common managed rule set.

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

# ── GuardDuty ─────────────────────────────────────────────────────────
# See environments/dev/security.tf for the full design rationale —
# identical here, just gated off by default (account+region singleton,
# var.owns_account_security_baseline). dev owns this today.

resource "aws_guardduty_detector" "main" {
  count = var.owns_account_security_baseline ? 1 : 0

  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = {
    Project     = "stagecraft"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count = var.owns_account_security_baseline ? 1 : 0

  name        = "${local.name}-guardduty-findings"
  description = "Routes GuardDuty findings (MEDIUM severity and above) to the alerts SNS topic"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 4] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  count = var.owns_account_security_baseline ? 1 : 0

  rule = aws_cloudwatch_event_rule.guardduty_findings[0].name
  arn  = aws_sns_topic.alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEventBridgePublish"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.alerts.arn
    }]
  })
}
