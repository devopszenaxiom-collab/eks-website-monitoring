variable "namespace" {
  type = string
}

variable "rule_labels" {
  description = "Labels the Prometheus needs on a PrometheusRule to load it. Empty is fine for the stack this package installs; an existing Prometheus usually needs its release label."
  type        = map(string)
  default     = {}
}

variable "install_rules" {
  type    = bool
  default = true
}

variable "install_dashboards" {
  type    = bool
  default = true
}

variable "dashboard_label" {
  description = "Label the Grafana dashboard sidecar looks for."
  type        = string
  default     = "grafana_dashboard"
}

variable "has_http_probes" {
  type = bool
}

variable "has_tcp_probes" {
  type = bool
}

variable "has_postgres" {
  type = bool
}

variable "has_redis" {
  type = bool
}
