# ── CloudTrail ────────────────────────────────────────────────────────
# Control-plane audit trail (every API call against this account) — pairs
# with VPC Flow Logs (network.tf) for the network-plane side. Multi-region:
# basically free relative to a single-region trail, and catches calls made
# in any region, including against global services (IAM, CloudFront) that
# don't have a "home" region.
#
# Needs its own S3 bucket — the only other S3 bucket in this project is the
# Terraform state bucket, created manually outside Terraform (see
# README's "Bootstrap" section). This one IS Terraform-managed since
# CloudTrail needs a fresh bucket with a specific policy, not a pre-existing
# one.

resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project     = "agora"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    id     = "expire-old-trail-logs"
    status = "Enabled"

    filter {}

    # Demo/dev project — 90 days is plenty of audit history without storage
    # cost creeping up indefinitely as the trail accumulates objects.
    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
    ]
  })
}

# Optional CloudWatch Logs integration — makes trail events queryable/
# alarmable (Logs Insights, metric filters) instead of only sitting in S3
# waiting to be downloaded.
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  name = "${local.name}-cloudtrail-cloudwatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "cloudtrail_to_cloudwatch" {
  name = "${local.name}-cloudtrail-cloudwatch"
  role = aws_iam_role.cloudtrail_to_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  name           = "${local.name}-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch.arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Project     = "agora"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}
