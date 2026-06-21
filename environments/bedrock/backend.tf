terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  backend "s3" {
    bucket         = "agora-tfstate-personal-591316257673"
    key            = "bedrock/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "agora-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  dynamic "assume_role" {
    for_each = var.assume_role_arn != "" ? [1] : []
    content {
      role_arn = var.assume_role_arn
    }
  }

  default_tags {
    tags = {
      Project     = "agora"
      Environment = "company"
      ManagedBy   = "terraform"
    }
  }
}
