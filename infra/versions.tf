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

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }

    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.50"
    }
  }

  # Configuracao vem por -backend-config no init: o nome do bucket contem o
  # id da conta e este repositorio e publico. Ver bootstrap/README.md.
  backend "s3" {}
}

provider "datadog" {
  api_key = trimspace(var.datadog_api_key) != "" ? var.datadog_api_key : null
  app_key = trimspace(var.datadog_app_key) != "" ? var.datadog_app_key : null
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

provider "helm" {
  kubernetes {
    host                   = try(aws_eks_cluster.principal[0].endpoint, "https://127.0.0.1")
    cluster_ca_certificate = try(base64decode(aws_eks_cluster.principal[0].certificate_authority[0].data), null)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        try(aws_eks_cluster.principal[0].name, "disabled"),
        "--region",
        var.region
      ]
    }
  }
}
