provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

  # Never register resource providers in a client's subscription. The default
  # registers a long list of unrelated ones on the first plan, which is a change
  # to their subscription that nobody asked for. Everything this package creates
  # in Azure (a managed identity and a role assignment) uses providers that are
  # registered on any subscription that already runs AKS.
  resource_provider_registrations = "none"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "kubectl" {
  config_path      = var.kubeconfig_path
  load_config_file = true
}
