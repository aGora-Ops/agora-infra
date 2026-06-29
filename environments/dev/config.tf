resource "aws_s3_bucket" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket        = "${local.name}-config-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project     = "stagecraft"
    Environment = local.env
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.config[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.config[0].id

  rule {
    id     = "expire-old-config-snapshots"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  bucket = aws_s3_bucket.config[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSConfigBucketPermissionsCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.config[0].arn
      },
      {
        Sid       = "AWSConfigBucketExistenceCheck"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.config[0].arn
      },
      {
        Sid       = "AWSConfigBucketDelivery"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.config[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
    ]
  })
}

resource "aws_iam_role" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-config-recorder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.owns_account_security_baseline ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "main" {
  count = var.owns_account_security_baseline ? 1 : 0

  name     = "${local.name}-config-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  count = var.owns_account_security_baseline ? 1 : 0

  name           = "${local.name}-config-channel"
  s3_bucket_name = aws_s3_bucket.config[0].id

  depends_on = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.config]
}

resource "aws_config_configuration_recorder_status" "main" {
  count = var.owns_account_security_baseline ? 1 : 0

  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_config_rule" "rds_encrypted" {
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-rds-storage-encrypted"

  source {
    owner             = "AWS"
    source_identifier = "RDS_STORAGE_ENCRYPTED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "s3_public_read_prohibited" {
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-s3-bucket-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "s3_public_write_prohibited" {
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-s3-bucket-public-write-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "restricted_ssh" {
  count = var.owns_account_security_baseline ? 1 : 0

  name = "${local.name}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

moved {
  from = aws_s3_bucket.config
  to   = aws_s3_bucket.config[0]
}

moved {
  from = aws_s3_bucket_public_access_block.config
  to   = aws_s3_bucket_public_access_block.config[0]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.config
  to   = aws_s3_bucket_lifecycle_configuration.config[0]
}

moved {
  from = aws_s3_bucket_policy.config
  to   = aws_s3_bucket_policy.config[0]
}

moved {
  from = aws_iam_role.config
  to   = aws_iam_role.config[0]
}

moved {
  from = aws_iam_role_policy_attachment.config
  to   = aws_iam_role_policy_attachment.config[0]
}

moved {
  from = aws_config_configuration_recorder.main
  to   = aws_config_configuration_recorder.main[0]
}

moved {
  from = aws_config_delivery_channel.main
  to   = aws_config_delivery_channel.main[0]
}

moved {
  from = aws_config_configuration_recorder_status.main
  to   = aws_config_configuration_recorder_status.main[0]
}

moved {
  from = aws_config_config_rule.rds_encrypted
  to   = aws_config_config_rule.rds_encrypted[0]
}

moved {
  from = aws_config_config_rule.s3_public_read_prohibited
  to   = aws_config_config_rule.s3_public_read_prohibited[0]
}

moved {
  from = aws_config_config_rule.s3_public_write_prohibited
  to   = aws_config_config_rule.s3_public_write_prohibited[0]
}

moved {
  from = aws_config_config_rule.restricted_ssh
  to   = aws_config_config_rule.restricted_ssh[0]
}
