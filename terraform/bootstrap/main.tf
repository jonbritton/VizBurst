terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "region" {
  description = "Region for the state backend. Keep it with the workloads (us-west-2)."
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.region
}

variable "tfstate_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state"
  type        = string
}

variable "tfstate_lock_table_name" {
  type    = string
  default = "devops-portfolio-tfstate-lock"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.tfstate_bucket_name
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# State files contain secrets — block the hoi polloi from peeping
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = coalesce(var.tfstate_lock_table_name, "${var.tfstate_bucket_name}-lock")
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "tfstate_bucket" { value = aws_s3_bucket.tfstate.id }
output "tfstate_lock_table" { value = aws_dynamodb_table.tfstate_lock.id }