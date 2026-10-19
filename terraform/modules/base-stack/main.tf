# ─────────────────────────────────────────────────────────────────────────────
# Base stack: Prometheus, Alertmanager and (optionally) Grafana, for a client
# who has none or wants ours kept apart from theirs.
#
# Installed with fullnameOverride = "zmon" so the service names are fixed:
#   zmon-prometheus:9090      (the agent writes here)
#   zmon-alertmanager:9093
# No ingress is created: nothing is exposed outside the cluster, so the
# remote-write receiver is reachable only from inside it.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    helm   = { source = "hashicorp/helm" }
    random = { source = "hashicorp/random" }
  }
}

locals {
  fullname      = "zmon"
  slack_enabled = nonsensitive(var.slack_webhook_url != "")
  tg_enabled    = nonsensitive(var.telegram_bot_token != "") && var.telegram_chat_id != ""
  warn_webhook  = var.slack_webhook_url_warning != "" ? var.slack_webhook_url_warning : var.slack_webhook_url
  warn_channel  = var.slack_channel_warning != "" ? var.slack_channel_warning : var.slack_channel

  slack_title = "{{ if eq .Status \"firing\" }}:rotating_light:{{ else }}:white_check_mark:{{ end }} [{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}"
  slack_text  = "{{ range .Alerts }}*{{ .Annotations.summary }}*\n{{ .Annotations.description }}\n{{ end }}"

  receivers = concat(
    [{ name = "null" }],
    local.slack_enabled || local.tg_enabled ? [merge(
      { name = "critical" },
      local.slack_enabled ? { slack_configs = [{
        api_url       = var.slack_webhook_url
        channel       = var.slack_channel
        send_resolved = true
        title         = local.slack_title
        text          = local.slack_text
      }] } : {},
      local.tg_enabled ? { telegram_configs = [{
        bot_token     = var.telegram_bot_token
        chat_id       = tonumber(var.telegram_chat_id)
        send_resolved = true
      }] } : {},
    )] : [],
    local.slack_enabled ? [{
      name = "warning"
      slack_configs = [{
        api_url       = local.warn_webhook
        channel       = local.warn_channel
        send_resolved = true
        title         = local.slack_title
        text          = local.slack_text
      }]
    }] : [],
  )

  routes = concat(
    # Watchdog always fires by design; it is for an outside heartbeat, not Slack.
    [{ receiver = "null", matchers = ["alertname = Watchdog"] }],
    local.slack_enabled || local.tg_enabled ? [{ receiver = "critical", matchers = ["severity = critical"] }] : [],
    local.slack_enabled ? [{ receiver = "warning", matchers = ["severity =~ \"warning|info\""] }] : [],
  )
}

resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

resource "helm_release" "stack" {
  name             = "zmon"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  namespace        = var.namespace
  timeout          = 900
  create_namespace = false

  values = [yamlencode({
    fullnameOverride = local.fullname

    prometheus = {
      prometheusSpec = merge({
        retention = var.retention
        # The agent pushes with remote_write.
        enableRemoteWriteReceiver = true
        # Pick up every PrometheusRule and ServiceMonitor in the cluster, not
        # only the ones this chart created, so ../content needs no special label.
        ruleSelectorNilUsesHelmValues           = false
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        storageSpec = {
          volumeClaimTemplate = {
            spec = merge(
              {
                accessModes = ["ReadWriteOnce"]
                resources   = { requests = { storage = var.storage_size } }
              },
              var.storage_class == "" ? {} : { storageClassName = var.storage_class }
            )
          }
        }
      }, {})
    }

    alertmanager = {
      config = {
        global = { resolve_timeout = "5m" }
        route = {
          receiver        = "null"
          group_by        = ["alertname", "target", "instance"]
          group_wait      = "30s"
          group_interval  = "5m"
          repeat_interval = "4h"
          routes          = local.routes
        }
        # One problem, one message: a service that is down silences the
        # warnings about the same service.
        inhibit_rules = [{
          source_matchers = ["severity = critical"]
          target_matchers = ["severity =~ \"warning|info\""]
          # Probe series all carry the agent's own instance name, so target
          # must match too or one site being down would silence every other.
          equal = ["instance", "target"]
        }]
        receivers = local.receivers
      }
    }

    grafana = {
      enabled       = var.install_grafana
      adminPassword = random_password.grafana_admin.result
      sidecar = {
        dashboards = { enabled = true, label = "grafana_dashboard", searchNamespace = "ALL" }
      }
    }

    defaultRules = {
      # Not reachable on a managed control plane; they would fire for ever.
      disabled = {
        KubeControllerManagerDown = true
        KubeSchedulerDown         = true
        KubeProxyDown             = true
      }
    }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false }
    kubeEtcd              = { enabled = false }
  })]
}
