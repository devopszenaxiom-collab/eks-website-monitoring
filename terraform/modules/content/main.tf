# ─────────────────────────────────────────────────────────────────────────────
# Alert rules and dashboards for what the agent collects.
#
# Rules are one PrometheusRule object; a group is only included when the agent
# actually collects that kind of data, so an "absent" rule can never fire for a
# collector that was never switched on.
#
# kubectl_manifest (not kubernetes_manifest) is used on purpose: it does not
# need the PrometheusRule CRD to exist at plan time, so rules and a brand-new
# Prometheus can be created in the same apply.
#
# Dashboards are ConfigMaps with the label the Grafana sidecar watches. That
# works for the Grafana this package installs and for any Grafana that runs
# the same sidecar; for any other Grafana, import the JSON files by hand.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    kubectl    = { source = "gavinbunney/kubectl" }
  }
}

locals {
  rule_groups = yamldecode(templatefile("${path.module}/rules.yaml.tftpl", {
    has_http_probes = var.has_http_probes
    has_tcp_probes  = var.has_tcp_probes
    has_postgres    = var.has_postgres
    has_redis       = var.has_redis
  }))

  dashboards = {
    "endpoints"  = var.has_http_probes || var.has_tcp_probes
    "postgresql" = var.has_postgres
    "redis"      = var.has_redis
  }
}

resource "kubectl_manifest" "rules" {
  count = var.install_rules ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "monitoring-agent-rules"
      namespace = var.namespace
      labels    = merge({ "app.kubernetes.io/part-of" = "monitoring-agent" }, var.rule_labels)
    }
    spec = local.rule_groups
  })
}

resource "kubernetes_config_map_v1" "dashboard" {
  for_each = { for name, wanted in local.dashboards : name => wanted if wanted && var.install_dashboards }

  metadata {
    name      = "monitoring-agent-dashboard-${each.key}"
    namespace = var.namespace
    labels = {
      (var.dashboard_label)       = "1"
      "app.kubernetes.io/part-of" = "monitoring-agent"
    }
  }

  data = {
    "${each.key}.json" = file("${path.module}/dashboards/${each.key}.json")
  }
}
