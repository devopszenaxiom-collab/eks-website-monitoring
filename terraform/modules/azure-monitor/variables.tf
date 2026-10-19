variable "subscription_id" {
  description = "Subscription the agent reads metrics from."
  type        = string
}

variable "aks_resource_group" {
  type = string
}

variable "aks_cluster_name" {
  type = string
}

variable "namespace" {
  description = "Namespace of the agent's service account."
  type        = string
}

variable "service_account_name" {
  description = "Service account the agent pod runs as."
  type        = string
  default     = "monitoring-agent"
}

variable "location" {
  description = "Region for the managed identity. Empty = the cluster's region."
  type        = string
  default     = ""
}
