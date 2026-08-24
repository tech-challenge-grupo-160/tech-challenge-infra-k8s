terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Sem backend remoto por design: este e o modulo que cria o backend.
  # O state fica local e nao e versionado - ver README.md.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Environment = "shared"
    }
  }
}
