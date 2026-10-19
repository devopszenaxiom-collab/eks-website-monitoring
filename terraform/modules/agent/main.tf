# ─────────────────────────────────────────────────────────────────────────────
# The agent: one Grafana Alloy pod that probes endpoints, logs in to PostgreSQL
# and Redis, optionally reads Azure Monitor, and pushes everything to Prometheus
# with remote_write.
#
# Label contract (the rules and dashboards in ../content depend on it):
#   http probes   job="blackbox"        target="<address>"
#   tcp probes    job="blackbox-tcp"    target="<address>"
#   postgres      job="postgres-exporter"  instance="<host>:<port>"  server="<name>"
#   redis         job="redis-exporter"     instance="<host>:<port>"  cache="<name>"
#   agent itself  job="alloy"
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_providers {
    kubernetes = { source = "hashicorp/kubernetes" }
    helm       = { source = "hashicorp/helm" }
  }
}

locals {
  # Probe modules. http_alive treats 401/403/404 as "up": an API that asks for a
  # login or has no root page is still alive. Only a network error, TLS error,
  # timeout or 5xx counts as down.
  blackbox_modules = {
    http_2xx = {
      prober  = "http"
      timeout = "5s"
      http = {
        preferred_ip_protocol = "ip4"
        valid_http_versions   = ["HTTP/1.1", "HTTP/2.0"]
      }
    }
    http_alive = {
      prober  = "http"
      timeout = "5s"
      http = {
        preferred_ip_protocol = "ip4"
        valid_http_versions   = ["HTTP/1.1", "HTTP/2.0"]
        valid_status_codes    = [200, 201, 301, 302, 401, 403, 404]
      }
    }
    tcp_connect = {
      prober  = "tcp"
      timeout = "5s"
      tcp     = { preferred_ip_protocol = "ip4" }
    }
    # TLS handshake on a raw port: reads the certificate the service really
    # presents and sends no protocol payload.
    tcp_tls = {
      prober  = "tcp"
      timeout = "5s"
      tcp = merge(
        { tls = true, preferred_ip_protocol = "ip4" },
        var.tls_server_name == "" ? {} : { tls_config = { server_name = var.tls_server_name } }
      )
    }
  }

  http_probes = [for p in var.probes : p if startswith(p.module, "http")]
  tcp_probes  = [for p in var.probes : p if startswith(p.module, "tcp")]

  # Read-only catalogue queries. No extension needed; they add table-bloat and
  # blocked-autovacuum signals the default collectors do not expose.
  postgres_queries = yamlencode({
    pg_table_bloat = {
      query  = "SELECT schemaname, relname, CASE WHEN (n_dead_tup + n_live_tup) > 0 THEN n_dead_tup::float / (n_dead_tup + n_live_tup) ELSE 0 END AS dead_ratio FROM pg_stat_user_tables WHERE (n_dead_tup + n_live_tup) > 50000 ORDER BY dead_ratio DESC LIMIT 15"
      master = true
      metrics = [
        { schemaname = { usage = "LABEL", description = "Schema" } },
        { relname = { usage = "LABEL", description = "Table" } },
        { dead_ratio = { usage = "GAUGE", description = "Dead-tuple ratio per table, tables over 50k rows" } },
      ]
    }
    pg_autovacuum_blocked = {
      query  = "SELECT count(*) AS blocked FROM pg_stat_activity WHERE query LIKE 'autovacuum:%' AND wait_event_type = 'Lock'"
      master = true
      metrics = [
        { blocked = { usage = "GAUGE", description = "Autovacuum workers blocked on a lock" } },
      ]
    }
  })

  workload_identity = var.azure_monitor.enabled && var.azure_monitor.auth == "workload_identity"
  service_principal = var.azure_monitor.enabled && var.azure_monitor.auth == "service_principal"

  config = templatefile("${path.module}/config.alloy.tftpl", {
    remote_write_url = var.remote_write_url
    external_labels  = var.external_labels
    http_probes      = local.http_probes
    tcp_probes       = local.tcp_probes
    postgres_targets = var.postgres_targets
    redis_targets    = var.redis_targets
    azure            = var.azure_monitor
  })

  secret_data = merge(
    {
      for i, t in var.postgres_targets :
      # urlencode(): a password containing @ : / ? # would break the URL form.
      "PG_DSN_${i}" => "postgresql://${t.username}:${urlencode(lookup(var.postgres_passwords, t.name, ""))}@${t.host}:${t.port}/${t.database}?sslmode=${t.sslmode}"
    },
    {
      for i, t in var.redis_targets :
      "REDIS_PASSWORD_${i}" => lookup(var.redis_passwords, t.name, "")
    },
    local.service_principal ? {
      AZURE_TENANT_ID     = var.azure_monitor.tenant_id
      AZURE_CLIENT_ID     = var.azure_monitor.client_id
      AZURE_CLIENT_SECRET = var.azure_monitor_client_secret
    } : {},
  )
}

resource "kubernetes_secret_v1" "agent" {
  metadata {
    name      = "monitoring-agent-credentials"
    namespace = var.namespace
  }
  type = "Opaque"
  data = local.secret_data
}

# config.alloy plus the two files it opens by path. The chart mounts the whole
# ConfigMap at /etc/alloy.
resource "kubernetes_config_map_v1" "agent" {
  metadata {
    name      = "monitoring-agent-config"
    namespace = var.namespace
  }
  data = {
    "config.alloy"          = local.config
    "blackbox.yml"          = yamlencode({ modules = local.blackbox_modules })
    "postgres-queries.yaml" = local.postgres_queries
  }
}

resource "helm_release" "agent" {
  name             = "monitoring-agent"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  version          = var.chart_version
  namespace        = var.namespace
  timeout          = 600
  create_namespace = false

  values = [yamlencode({
    fullnameOverride = "monitoring-agent"
    # Every target is a fixed address, so the pod needs no Kubernetes API access.
    crds = { create = false }
    rbac = { create = false }
    serviceAccount = {
      # Workload identity injects its token through the service account.
      automountServiceAccountToken = local.workload_identity
      annotations = local.workload_identity ? {
        "azure.workload.identity/client-id" = var.azure_monitor.client_id
      } : {}
    }
    controller = {
      type     = "deployment"
      replicas = 1
      # Two pods at once would push the same series and Prometheus rejects the
      # overlap, so replace rather than roll.
      updateStrategy = { type = "Recreate" }
      podLabels = local.workload_identity ? {
        "azure.workload.identity/use" = "true"
      } : {}
      # Restart the pod when the configuration or a credential changes.
      podAnnotations = {
        "checksum/config" = sha256(jsonencode(kubernetes_config_map_v1.agent.data))
        "checksum/secret" = sha256(jsonencode(local.secret_data))
      }
    }
    alloy = {
      configMap = {
        create = false
        name   = kubernetes_config_map_v1.agent.metadata[0].name
        key    = "config.alloy"
      }
      enableReporting = false
      envFrom         = [{ secretRef = { name = kubernetes_secret_v1.agent.metadata[0].name } }]
      resources       = var.resources
    }
  })]

  lifecycle {
    precondition {
      condition     = alltrue([for t in var.postgres_targets : contains(keys(nonsensitive(var.postgres_passwords)), t.name)])
      error_message = "Every entry in postgres_targets needs a password in postgres_passwords under the same name."
    }
    precondition {
      condition     = !var.azure_monitor.enabled || contains(["workload_identity", "service_principal"], var.azure_monitor.auth)
      error_message = "azure_monitor.auth must be \"workload_identity\" or \"service_principal\"."
    }
    precondition {
      condition     = !var.azure_monitor.enabled || var.azure_monitor.client_id != ""
      error_message = "Azure Monitor is enabled but no client_id was given for the agent to sign in with."
    }
  }
}
