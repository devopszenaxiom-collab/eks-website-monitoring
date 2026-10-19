# ── Where to install ─────────────────────────────────────────────────────────
variable "subscription_id" {
  description = "The client's Azure subscription."
  type        = string
}

variable "aks_resource_group" {
  description = "Resource group of the AKS cluster."
  type        = string
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster the agent runs in."
  type        = string
}

variable "kubeconfig_path" {
  description = "kubeconfig for that cluster. The pipeline writes it; leave the default when running by hand."
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "Namespace for everything this package installs."
  type        = string
  default     = "monitoring"
}

variable "create_namespace" {
  description = "Create the namespace. Set false when it already exists (discovery sets this)."
  type        = bool
  default     = true
}

# ── Existing tools or ours ───────────────────────────────────────────────────
variable "prometheus_mode" {
  description = "\"install\" = install our Prometheus and Alertmanager. \"existing\" = use the client's."
  type        = string
  default     = "install"

  validation {
    condition     = contains(["install", "existing"], var.prometheus_mode)
    error_message = "prometheus_mode must be \"install\" or \"existing\". (\"auto\" is resolved by scripts/discover.sh before Terraform runs.)"
  }
}

variable "existing_prometheus_remote_write_url" {
  description = "For prometheus_mode = \"existing\": the client's remote-write endpoint. Discovery fills this in."
  type        = string
  default     = ""
}

variable "existing_prometheus_rule_labels" {
  description = "For prometheus_mode = \"existing\": labels their Prometheus needs on a rule to load it. Discovery fills this in."
  type        = map(string)
  default     = {}
}

variable "grafana_mode" {
  description = "\"install\" = install Grafana (only with prometheus_mode = \"install\"). \"existing\" = add dashboards for the client's Grafana. \"none\" = no dashboards."
  type        = string
  default     = "install"

  validation {
    condition     = contains(["install", "existing", "none"], var.grafana_mode)
    error_message = "grafana_mode must be \"install\", \"existing\" or \"none\"."
  }
}

variable "install_rules" {
  description = "Install our alert rules."
  type        = bool
  default     = true
}

# ── Base stack settings (only when prometheus_mode = "install") ──────────────
variable "stack_chart_version" {
  description = "kube-prometheus-stack chart version."
  type        = string
  default     = "65.5.0"
}

variable "prometheus_retention" {
  type    = string
  default = "10d"
}

variable "prometheus_storage_size" {
  type    = string
  default = "20Gi"
}

variable "prometheus_storage_class" {
  type    = string
  default = ""
}

variable "slack_webhook_url" {
  type      = string
  default   = ""
  sensitive = true
}

variable "slack_channel" {
  type    = string
  default = ""
}

variable "slack_webhook_url_warning" {
  type      = string
  default   = ""
  sensitive = true
}

variable "slack_channel_warning" {
  type    = string
  default = ""
}

variable "telegram_bot_token" {
  type      = string
  default   = ""
  sensitive = true
}

variable "telegram_chat_id" {
  type    = string
  default = ""
}

# ── The agent ────────────────────────────────────────────────────────────────
variable "alloy_chart_version" {
  description = "grafana/alloy chart version."
  type        = string
  default     = "1.13.1"
}

variable "external_labels" {
  description = "Labels added to everything the agent writes."
  type        = map(string)
  default     = {}
}

variable "probes" {
  description = "Endpoints to probe: name, address, and module (http_alive, http_2xx, tcp_connect, tcp_tls)."
  type = list(object({
    name    = string
    address = string
    module  = optional(string, "http_alive")
  }))
  default = []
}

variable "tls_server_name" {
  description = "Certificate name to verify tcp_tls probes against, when the address itself is not in the certificate."
  type        = string
  default     = ""
}

variable "postgres_targets" {
  description = "PostgreSQL servers to watch. Use a read-only login with the pg_monitor role."
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
  description = "Password per PostgreSQL target name. Comes from the secret store, never from a file in the repository."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "redis_targets" {
  description = "Redis caches to watch."
  type = list(object({
    name = string
    host = string
    port = optional(number, 6380)
    tls  = optional(bool, true)
  }))
  default = []
}

variable "redis_passwords" {
  description = "Access key per Redis target name. Comes from the secret store."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ── Azure Monitor (optional) ─────────────────────────────────────────────────
variable "enable_azure_monitor" {
  description = "Also read Azure Monitor metrics. false = direct checks only."
  type        = bool
  default     = false
}

variable "azure_monitor_auth" {
  description = "\"service_principal\" = the client gives an existing client id and secret; nothing is created in Azure or changed on the cluster. \"workload_identity\" = a managed identity with no stored password; needs the cluster's OIDC issuer."
  type        = string
  default     = "service_principal"
}

variable "azure_monitor_client_id" {
  description = "service_principal only: client id that already has Monitoring Reader on the subscription."
  type        = string
  default     = ""
}

variable "azure_monitor_tenant_id" {
  description = "service_principal only: tenant id."
  type        = string
  default     = ""
}

variable "azure_monitor_client_secret" {
  description = "service_principal only: client secret. Comes from the secret store."
  type        = string
  default     = ""
  sensitive   = true
}

variable "azure_resource_types" {
  description = "Azure resource types and metrics the agent reads. Metric names must match Azure's metric definitions for the type."
  type = list(object({
    name          = string
    resource_type = string
    metrics       = list(string)
  }))
  default = [
    { name = "postgres", resource_type = "Microsoft.DBforPostgreSQL/flexibleServers", metrics = ["cpu_percent", "memory_percent", "storage_percent", "active_connections", "is_db_alive"] },
    { name = "redis", resource_type = "Microsoft.Cache/Redis", metrics = ["usedmemorypercentage", "serverLoad", "connectedclients", "percentProcessorTime"] },
    { name = "appgw", resource_type = "Microsoft.Network/applicationGateways", metrics = ["HealthyHostCount", "UnhealthyHostCount", "FailedRequests", "TotalRequests"] },
    { name = "loadbalancer", resource_type = "Microsoft.Network/loadBalancers", metrics = ["VipAvailability", "DipAvailability", "SnatConnectionCount"] },
    { name = "keyvault", resource_type = "Microsoft.KeyVault/vaults", metrics = ["Availability", "ServiceApiLatency", "SaturationShoebox"] },
    { name = "storage", resource_type = "Microsoft.Storage/storageAccounts", metrics = ["Availability", "UsedCapacity", "Transactions", "SuccessE2ELatency"] },
    { name = "acr", resource_type = "Microsoft.ContainerRegistry/registries", metrics = ["TotalPullCount", "SuccessfulPullCount", "StorageUsed"] },
    { name = "vmss", resource_type = "Microsoft.Compute/virtualMachineScaleSets", metrics = ["Percentage CPU", "Available Memory Bytes"] },
    { name = "publicip", resource_type = "Microsoft.Network/publicIPAddresses", metrics = ["IfUnderDDoSAttack", "VipAvailability"] },
  ]
}
