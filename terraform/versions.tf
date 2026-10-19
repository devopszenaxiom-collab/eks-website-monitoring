terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm    = { source = "hashicorp/azurerm", version = "~> 4.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.15" }
    kubectl    = { source = "gavinbunney/kubectl", version = "~> 1.14" }
    random     = { source = "hashicorp/random", version = "~> 3.6" }
  }
}
