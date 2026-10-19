# ─────────────────────────────────────────────────────────────────────────────
# Monitoring agent package — root.
#
# Wires four modules together according to the choices made for the client:
#   base-stack     only when prometheus_mode = "install"
#   azure-monitor  only when Azure Monitor is on with workload identity
#   agent          always
#   content        alert rules and dashboards for what the agent collects
# ─────────────────────────────────────────────────────────────────────────────

locals {
  install_stack     = var.prometheus_mode == "install"
  workload_identity = var.enable_azure_monitor && var.azure_monitor_auth == "workload_identity"

  remote_write_url = local.install_stack ? module.base_stack[0].remote_write_url : var.existing_prometheus_remote_write_url
  namespace        = var.create_namespace ? kubernetes_namespace_v1.this[0].metadata[0].name : var.namespace
}

# Checks on the combination of choices, before anything is created.
resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition     = local.install_stack || var.existing_prometheus_remote_write_url != ""
      error_message = "prometheus_mode = \"existing\" needs existing_prometheus_remote_write_url. Run scripts/discover.sh, or set it in the client file."
    }
    precondition {
      condition     = var.grafana_mode != "install" || local.install_stack
      error_message = "grafana_mode = \"install\" is only available together with prometheus_mode = \"install\" in this version. With an existing Prometheus use grafana_mode = \"existing\" or \"none\"."
    }
  }
}

resource "kubernetes_namespace_v1" "this" {
  count      = var.create_namespace ? 1 : 0
  depends_on = [terraform_data.guard]

  metadata {
    name   = var.namespace
    labels = { "app.kubernetes.io/part-of" = "monitoring-agent" }
  }
}

module "base_stack" {
  source = "./modules/base-stack"
  count  = local.install_stack ? 1 : 0

  namespace       = local.namespace
  chart_version   = var.stack_chart_version
  retention       = var.prometheus_retention
  storage_size    = var.prometheus_storage_size
  storage_class   = var.prometheus_storage_class
  install_grafana = var.grafana_mode == "install"

  slack_webhook_url         = var.slack_webhook_url
  slack_channel             = var.slack_channel
  slack_webhook_url_warning = var.slack_webhook_url_warning
  slack_channel_warning     = var.slack_channel_warning
  telegram_bot_token        = var.telegram_bot_token
  telegram_chat_id          = var.telegram_chat_id
}

module "azure_monitor" {
  source = "./modules/azure-monitor"
  count  = local.workload_identity ? 1 : 0

  subscription_id    = var.subscription_id
  aks_resource_group = var.aks_resource_group
  aks_cluster_name   = var.aks_cluster_name
  namespace          = var.namespace
}

module "agent" {
  source = "./modules/agent"

  namespace        = local.namespace
  chart_version    = var.alloy_chart_version
  remote_write_url = local.remote_write_url
  external_labels  = var.external_labels

  probes          = var.probes
  tls_server_name = var.tls_server_name

  postgres_targets   = var.postgres_targets
  postgres_passwords = var.postgres_passwords
  redis_targets      = var.redis_targets
  redis_passwords    = var.redis_passwords

  azure_monitor = {
    enabled         = var.enable_azure_monitor
    subscription_id = var.subscription_id
    auth            = var.azure_monitor_auth
    client_id       = local.workload_identity ? module.azure_monitor[0].client_id : var.azure_monitor_client_id
    tenant_id       = local.workload_identity ? module.azure_monitor[0].tenant_id : var.azure_monitor_tenant_id
    resource_types  = var.azure_resource_types
  }
  azure_monitor_client_secret = var.azure_monitor_client_secret
}

module "content" {
  source = "./modules/content"

  namespace          = local.namespace
  install_rules      = var.install_rules
  install_dashboards = var.grafana_mode != "none"
  rule_labels        = local.install_stack ? {} : var.existing_prometheus_rule_labels

  has_http_probes = length([for p in var.probes : p if startswith(p.module, "http")]) > 0
  has_tcp_probes  = length([for p in var.probes : p if startswith(p.module, "tcp")]) > 0
  has_postgres    = length(var.postgres_targets) > 0
  has_redis       = length(var.redis_targets) > 0

  # Rules need the PrometheusRule CRD, which our own stack brings.
  depends_on = [module.base_stack]
}
