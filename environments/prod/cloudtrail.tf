# ── CloudTrail ────────────────────────────────────────────────────────
# Control-plane audit trail. See environments/dev/cloudtrail.tf for the full
# design rationale (multi-region, own S3 bucket, optional CloudWatch Logs
# integration) — identical here, just gated off by default.
#
# Account+region singleton — gated by var.owns_account_security_baseline so
# dev and prod (same AWS account) never both try to create one. dev owns
# this today; see that variable's comment in variables.tf.

resource "aws_s3_bucket" "cloudtrail" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket        = "${local.name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project     = "stagecraft"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  rule {
    id     = "expire-old-trail-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "cloudtrail" {
  count = var.owns_account_security_baseline ? 1 : 0

  name              = "/aws/cloudtrail/${local.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "cloudtrail_to_cloudwatch" {
  count = var.owns_account_security_baseline ? 1 : 0

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
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-cloudtrail-cloudwatch"
  role = aws_iam_role.cloudtrail_to_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
    }]
  })
}

resource "aws_cloudtrail" "main" {
  count = var.owns_account_security_baseline ? 1 : 0

  name           = "${local.name}-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail[0].id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail[0].arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_to_cloudwatch[0].arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]

  tags = {
    Project     = "stagecraft"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}
