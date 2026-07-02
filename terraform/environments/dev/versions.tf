terraform {
  required_version = ">= 1.6.0" # OpenTofu

  # Partial backend config: pass the bucket/table created by ../../bootstrap via
  #   tofu init -backend-config=backend.hcl
  # (see backend.hcl.example)
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
