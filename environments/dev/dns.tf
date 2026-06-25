data "aws_route53_zone" "main" {
  count   = var.hosted_zone_id != "" ? 1 : 0
  zone_id = var.hosted_zone_id
}
