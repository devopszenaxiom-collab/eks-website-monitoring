output "namespace" {
  value = local.namespace
}

output "remote_write_url" {
  description = "Where the agent writes."
  value       = local.remote_write_url
}

output "agent_jobs" {
  description = "Job labels the agent writes; scripts/verify.sh checks each one."
  value       = module.agent.jobs
}

output "prometheus_service" {
  description = "Prometheus service name when this package installed it."
  value       = local.install_stack ? module.base_stack[0].prometheus_service : ""
}

output "alertmanager_service" {
  value = local.install_stack ? module.base_stack[0].alertmanager_service : ""
}

output "grafana_admin_password" {
  description = "Admin password of the Grafana this package installed."
  value       = local.install_stack && var.grafana_mode == "install" ? module.base_stack[0].grafana_admin_password : ""
  sensitive   = true
}
