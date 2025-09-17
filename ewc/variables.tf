variable "rancher_token" {
  description = "Rancher instance access key"
  type        = string
  sensitive   = true
}

variable "rancher_insecure" {
  description = "Is Rancher instance insecure"
  type        = bool
  default     = false
}

variable "kubeconfig_path" {
  description = "Path to your kubeconfig"
  type        = string
  default     = "~/.kube/config"
  validation {
    condition     = fileexists(var.kubeconfig_path)
    error_message = "The specified kubeconfig file does not exist."
  }
}

variable "cluster_name" {
  description = "Identifier for the cluster"
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for cert-manager"
  type        = string
  default     = "meteogate.eu"
}
