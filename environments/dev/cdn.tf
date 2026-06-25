resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.nlb_hostname != "" ? 1 : 0

  name  = "${local.name}-cloudfront-waf"
  scope = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "AllowGitHubWebhooks"
    priority = 0

    action {
      allow {}
    }

    statement {
      byte_match_statement {
        search_string = "/webhooks/github"
        field_to_match {
          uri_path {}
        }
        text_transformation {
          priority = 0
          type     = "NONE"
        }
        positional_constraint = "STARTS_WITH"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-allow-github-webhooks"
      sampled_requests_enabled   = true
    }
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
      metric_name                = "${local.name}-cloudfront-common-rules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-cloudfront-waf"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "main" {
  count = var.nlb_hostname != "" ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name} — CloudFront in front of the kGateway NLB"
  web_acl_id      = aws_wafv2_web_acl.cloudfront[0].arn

  aliases = var.domain_name != "" ? [
    var.domain_name,
    "argocd.${var.domain_name}",
    "grafana.${var.domain_name}",
  ] : []

  origin {
    domain_name = var.nlb_hostname
    origin_id   = "${local.name}-nlb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${local.name}-nlb"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "cdn_alias" {
  count = var.nlb_hostname != "" && var.hosted_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = aws_cloudfront_distribution.main[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "argocd_alias" {
  count = var.nlb_hostname != "" && var.hosted_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "argocd.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = aws_cloudfront_distribution.main[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "grafana_alias" {
  count = var.nlb_hostname != "" && var.hosted_zone_id != "" && var.domain_name != "" ? 1 : 0

  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = "grafana.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main[0].domain_name
    zone_id                = aws_cloudfront_distribution.main[0].hosted_zone_id
    evaluate_target_health = false
  }
}
