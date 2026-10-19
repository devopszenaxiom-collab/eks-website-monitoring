variable "namespace" {
  type = string
}

variable "chart_version" {
  description = "kube-prometheus-stack Helm chart version."
  type        = string
}

variable "retention" {
  description = "How long Prometheus keeps data."
  type        = string
  default     = "10d"
}

variable "storage_size" {
  description = "Disk for Prometheus."
  type        = string
  default     = "20Gi"
}

variable "storage_class" {
  description = "Storage class for the Prometheus disk. Empty = cluster default."
  type        = string
  default     = ""
}

variable "install_grafana" {
  description = "Install Grafana with the stack."
  type        = bool
  default     = true
}

variable "slack_webhook_url" {
  description = "Slack webhook for critical alerts. Empty = alerts are evaluated but not sent."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel" {
  type    = string
  default = ""
}

variable "slack_webhook_url_warning" {
  description = "Slack webhook for warning alerts. Empty = warnings go to the critical channel."
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_channel_warning" {
  type    = string
  default = ""
}

variable "telegram_bot_token" {
  description = "Telegram bot token for critical alerts. Empty = no Telegram."
  type        = string
  default     = ""
  sensitive   = true
}

variable "telegram_chat_id" {
  type    = string
  default = ""
}
