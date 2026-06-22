# ── CDN (CloudFront + WAF) ───────────────────────────────────────────
# CloudFront in front of the kGateway NLB: terminates TLS using your
# manually-created ACM cert, and is the only way to attach WAF protection
# to an NLB (WAFv2 REGIONAL doesn't support NLBs directly — CLOUDFRONT scope
# does). Origin traffic to the NLB stays plain HTTP, matching the NLB/Gateway
# setup exactly as it is today — nothing about the existing traffic path
# changes. Entirely optional: skipped when var.nlb_hostname is empty.

# CLOUDFRONT-scope Web ACLs must be created in us-east-1. This project
# already runs in us-east-1 (var.aws_region), so no provider alias is
# needed — but if that ever changes, this resource would need one.
resource "aws_wafv2_web_acl" "cloudfront" {
  count = var.nlb_hostname != "" ? 1 : 0

  name  = "${local.name}-cloudfront-waf"
  scope = "CLOUDFRONT"

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

  aliases = var.domain_name != "" ? [var.domain_name] : []

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

    # API/app traffic — don't cache by default, forward everything through.
    # Static asset caching can be tuned later with path-based behaviors if
    # the frontend serves cacheable assets directly through this domain.
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
