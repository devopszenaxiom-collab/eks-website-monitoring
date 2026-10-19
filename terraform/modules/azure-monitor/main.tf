# ─────────────────────────────────────────────────────────────────────────────
# Azure Monitor sign-in for the agent, workload-identity method.
#
# Creates a user-assigned identity, lets the agent's Kubernetes service account
# sign in as it (federated credential, so no stored password), and gives it
# Monitoring Reader on the subscription: read metrics, change nothing.
#
# Not used for the service-principal method: there the client supplies an
# existing client id and secret, and this module creates nothing.
#
# REQUIRES the cluster's OIDC issuer and workload identity to be on already.
# This module does not switch them on: that restarts the API server once and
# cannot be undone, so it is the client's decision, made outside this run.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm" }
  }
}

data "azurerm_kubernetes_cluster" "this" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group
}

resource "azurerm_user_assigned_identity" "agent" {
  name                = "id-monitoring-agent-${var.aks_cluster_name}"
  resource_group_name = var.aks_resource_group
  location            = var.location != "" ? var.location : data.azurerm_kubernetes_cluster.this.location

  lifecycle {
    precondition {
      condition     = data.azurerm_kubernetes_cluster.this.oidc_issuer_enabled
      error_message = "The AKS cluster has no OIDC issuer, which workload identity needs. Either enable it on the cluster first (one API server restart, cannot be undone), or use azure_monitor_auth = \"service_principal\"."
    }
  }
}

resource "azurerm_federated_identity_credential" "agent" {
  name                = "monitoring-agent"
  resource_group_name = var.aks_resource_group
  parent_id           = azurerm_user_assigned_identity.agent.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = data.azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
}

resource "azurerm_role_assignment" "monitoring_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.agent.principal_id
  principal_type       = "ServicePrincipal"
}
