# ── Security (WAF) ───────────────────────────────────────────────────
# Regional WAFv2 Web ACL with the AWS common managed rule set. Created here;
# attach to a CloudFront distribution (CLOUDFRONT scope) or ALB to enforce.

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
# Account-wide threat detection (compromised credentials, crypto-mining,
# anomalous API calls, etc.) — was a documented known gap. One detector per
# region per account; this fails to apply if a detector already exists
# outside Terraform (confirmed clean via `aws guardduty list-detectors`
# before adding this).

resource "aws_guardduty_detector" "main" {
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
    Project     = "agora"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

# Reuses the existing SNS alert topic (messaging.tf) rather than creating a
# second one — GuardDuty findings land in the same inbox as RDS/SQS alarms.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
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
  rule = aws_cloudwatch_event_rule.guardduty_findings.name
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
