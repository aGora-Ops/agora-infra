# ── DNS / TLS (ACM) ──────────────────────────────────────────────────
# Optional — only created when var.domain_name is set. Issues a wildcard
# cert validated via Route53.

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.3"

  count = var.domain_name != "" ? 1 : 0

  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]

  create_route53_records = true
  validation_method      = "DNS"
  wait_for_validation    = true
}
