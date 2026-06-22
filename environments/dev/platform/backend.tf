terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }

  backend "s3" {
    bucket         = "agora-tfstate-personal-591316257673"
    key            = "dev-platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "agora-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "agora"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "chriss"
    }
  }
}
