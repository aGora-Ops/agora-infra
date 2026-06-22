# ── DNS / TLS (ACM) ──────────────────────────────────────────────────
# The hosted zone and ACM certificate are created and validated manually
# (outside Terraform, cert must be in us-east-1 for CloudFront) — pass their
# IDs/ARN via tfvars (var.hosted_zone_id, var.acm_certificate_arn in cdn.tf).
# Terraform never owns their lifecycle, so it can't touch resources you
# manage by hand. The zone is only read back here to create the CloudFront
# alias record; both are optional — CloudFront/DNS are skipped entirely when
# left empty (see cdn.tf).

data "aws_route53_zone" "main" {
  count   = var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
}
