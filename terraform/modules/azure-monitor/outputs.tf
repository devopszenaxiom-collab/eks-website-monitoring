output "client_id" {
  description = "Client id the agent signs in with."
  value       = azurerm_user_assigned_identity.agent.client_id
}

output "tenant_id" {
  value = azurerm_user_assigned_identity.agent.tenant_id
}
