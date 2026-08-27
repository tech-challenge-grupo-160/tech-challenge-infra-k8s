terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Configuracao vem por -backend-config no init: o nome do bucket contem o
  # id da conta e este repositorio e publico. Ver bootstrap/README.md.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.ambiente
      ManagedBy   = "terraform"
    }
  }
}
