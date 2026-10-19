variable "namespace" {
  description = "Namespace the agent runs in."
  type        = string
}

variable "chart_version" {
  description = "grafana/alloy Helm chart version."
  type        = string
}

variable "remote_write_url" {
  description = "Prometheus remote-write endpoint the agent pushes to."
  type        = string
}

variable "external_labels" {
  description = "Labels added to every series the agent writes (for example environment = \"prod\")."
  type        = map(string)
  default     = {}
}

variable "probes" {
  description = "Endpoints to probe. module is one of the keys of local.blackbox_modules."
  type = list(object({
    name    = string
    address = string
    module  = optional(string, "http_alive")
  }))
  default = []
}

variable "tls_server_name" {
  description = "Name to verify the certificate against for tcp_tls probes, when the probed address is not in the certificate. Empty = verify against the address."
  type        = string
  default     = ""
}

variable "postgres_targets" {
  description = "PostgreSQL servers to collect from. Passwords come from postgres_passwords, keyed by name."
  type = list(object({
    name     = string
    host     = string
    port     = optional(number, 5432)
    database = optional(string, "postgres")
    username = string
    sslmode  = optional(string, "require")
  }))
  default = []
}

variable "postgres_passwords" {
  description = "Password per PostgreSQL target name."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "redis_targets" {
  description = "Redis caches to collect from. Passwords come from redis_passwords, keyed by name."
  type = list(object({
    name = string
    host = string
    port = optional(number, 6380)
    tls  = optional(bool, true)
  }))
  default = []
}

variable "redis_passwords" {
  description = "Access key per Redis target name."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "azure_monitor" {
  description = "Azure Monitor reader. Leave enabled = false for direct checks only."
  type = object({
    enabled         = bool
    subscription_id = string
    # "workload_identity" or "service_principal"
    auth      = string
    client_id = string
    tenant_id = string
    resource_types = list(object({
      name          = string
      resource_type = string
      metrics       = list(string)
    }))
  })
  default = {
    enabled         = false
    subscription_id = ""
    auth            = "service_principal"
    client_id       = ""
    tenant_id       = ""
    resource_types  = []
  }
}

variable "azure_monitor_client_secret" {
  description = "Client secret, only for azure_monitor.auth = \"service_principal\"."
  type        = string
  default     = ""
  sensitive   = true
}

variable "resources" {
  description = "Requests and limits for the agent container."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = {
    requests = { cpu = "50m", memory = "192Mi" }
    limits   = { cpu = "500m", memory = "512Mi" }
  }
}
