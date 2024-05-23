terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.29.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11.0"
    }

    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 4.1.0"
    }
  }

  required_version = "~> 1.3"
}
