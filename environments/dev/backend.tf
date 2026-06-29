terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  backend "s3" {
    bucket         = "stagecraft-tfstate-personal-591316257673"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "stagecraft-tf-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "stagecraft"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "chriss"
    }
  }
}

provider "time" {}
