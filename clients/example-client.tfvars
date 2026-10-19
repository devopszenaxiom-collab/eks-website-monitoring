# ─────────────────────────────────────────────────────────────────────────────
# One file per client. Copy this file, rename it, and fill it in.
#
# NO SECRETS IN THIS FILE. Passwords, keys and webhooks come from the pipeline's
# secret variable group (see docs/onboarding.md).
#
# Things discovery works out for you are NOT set here: whether Prometheus
# exists, its address, and whether the namespace must be created.
# ─────────────────────────────────────────────────────────────────────────────

# Added to every metric, so dashboards can tell environments apart.
external_labels = {
  environment = "production"
}

# Websites, APIs and ports to check every 30 seconds.
#   http_alive   up if it answers at all, including 401 / 403 / 404
#   http_2xx     up only on a 2xx answer
#   tcp_connect  the port accepts a connection
#   tcp_tls      the port completes a TLS handshake (also reads the certificate)
probes = [
  { name = "website", address = "https://www.example.com/", module = "http_2xx" },
  { name = "api", address = "https://api.example.com/health", module = "http_2xx" },
  { name = "admin", address = "https://admin.example.com/", module = "http_alive" },
  { name = "database-port", address = "psql-example.postgres.database.azure.com:5432", module = "tcp_connect" },
]

# PostgreSQL servers. Use a login that has only the pg_monitor role.
# Its password goes in the secret group as PG_PASSWORDS_JSON = {"main":"..."}.
postgres_targets = [
  { name = "main", host = "psql-example.postgres.database.azure.com", username = "monitoring" },
]

# Redis caches. The access key goes in the secret group as
# REDIS_PASSWORDS_JSON = {"main":"..."}.
redis_targets = [
  { name = "main", host = "redis-example.redis.cache.windows.net", port = 6380, tls = true },
]

# Slack channel names (the webhook URLs themselves are secrets).
slack_channel         = "#alerts"
slack_channel_warning = "#alerts-warning"

# Prometheus disk and history, used only when this package installs Prometheus.
prometheus_retention    = "10d"
prometheus_storage_size = "20Gi"
