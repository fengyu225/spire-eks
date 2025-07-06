terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.12.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
  }

  cloud {
    organization = "yu-feng-tfe"
    workspaces {
      name = "spire"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Management  = "Terraform"
      Project     = "SPIRE"
      Environment = var.environment
    }
  }
}

# Use exec-based authentication for Kubernetes provider
provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks.cluster_certificate_authority_data), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      try(module.eks.cluster_name, "dummy")
    ]
  }
}