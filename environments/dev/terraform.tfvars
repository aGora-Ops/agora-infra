aws_region         = "us-east-1"
cluster_name       = "agora-dev"
vpc_cidr           = "10.0.0.0/16"
kubernetes_version = "1.30"
domain_name        = "" # set your real domain — required for the CloudFront alias + ACM cert below
log_retention_days = 14
enable_karpenter   = true # IAM only — see compute.tf. Apply, then enable the platform-layer Helm release + NodePool.

# CloudFront + WAF (cdn.tf) — all three must be set to create the distribution.
# nlb_hostname: `kubectl get svc -n kgateway-system` after the platform layer is applied.
# hosted_zone_id / acm_certificate_arn: create the Route53 zone and validate the ACM
# cert (us-east-1) manually, then paste their IDs here. Leave nlb_hostname empty to
# skip CloudFront/WAF-for-CloudFront entirely.
nlb_hostname        = ""
hosted_zone_id      = ""
acm_certificate_arn = ""
