output "remote_write_url" {
  description = "Where the agent writes."
  value       = "http://${local.fullname}-prometheus.${var.namespace}.svc:9090/api/v1/write"
  depends_on  = [helm_release.stack]
}

output "prometheus_service" {
  value = "${local.fullname}-prometheus"
}

output "alertmanager_service" {
  value = "${local.fullname}-alertmanager"
}

output "grafana_admin_password" {
  value     = random_password.grafana_admin.result
  sensitive = true
}
