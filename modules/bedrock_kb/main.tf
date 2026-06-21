resource "aws_s3_bucket" "kb" {
  bucket = "agora-knowledge-base-${var.account_id}-${var.environment}"

  tags = { Project = "agora", Environment = var.environment, Purpose = "bedrock-kb" }
}

resource "aws_s3_bucket_public_access_block" "kb" {
  bucket = aws_s3_bucket.kb.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kb" {
  bucket = aws_s3_bucket.kb.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_opensearchserverless_security_policy" "encryption" {
  name = "agora-${var.environment}-enc"
  type = "encryption"
  policy = jsonencode({
    Rules       = [{ ResourceType = "collection", Resource = ["collection/agora-${var.environment}"] }]
    AWSOwnedKey = true
  })
}

resource "aws_opensearchserverless_security_policy" "network" {
  name = "agora-${var.environment}-net"
  type = "network"
  policy = jsonencode([{
    Rules = [
      { ResourceType = "collection", Resource = ["collection/agora-${var.environment}"] },
      { ResourceType = "dashboard", Resource = ["collection/agora-${var.environment}"] },
    ]
    AllowFromPublic = false
    SourceVPCEs     = [var.opensearch_vpc_endpoint_id]
  }])
}

resource "aws_opensearchserverless_collection" "main" {
  name = "agora-${var.environment}"
  type = "VECTORSEARCH"

  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
  ]

  tags = { Project = "agora", Environment = var.environment }
}

resource "aws_iam_role" "kb" {
  name = "agora-${var.environment}-bedrock-kb"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
      }
    }]
  })
}

resource "aws_iam_role_policy" "kb_s3" {
  name = "kb-s3"
  role = aws_iam_role.kb.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.kb.arn, "${aws_s3_bucket.kb.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["aoss:APIAccessAll"]
        Resource = aws_opensearchserverless_collection.main.arn
      },
    ]
  })
}

resource "aws_bedrockagent_knowledge_base" "main" {
  name     = "agora-${var.environment}-remediations"
  role_arn = aws_iam_role.kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.titan-embed-text-v2:0"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.main.arn
      vector_index_name = "agora-remediations"
      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = { Project = "agora", Environment = var.environment }
}

resource "aws_bedrockagent_data_source" "s3" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "agora-remediations-s3"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = aws_s3_bucket.kb.arn
    }
  }
}
