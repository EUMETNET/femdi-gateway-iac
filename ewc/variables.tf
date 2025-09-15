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

variable "route53_access_key" {
  description = "AWS access key for route53"
  type        = string
  sensitive   = true
}

variable "route53_secret_key" {
  description = "AWS secret key for route53"
  type        = string
  sensitive   = true
}

variable "route53_zone_id_filter" {
  description = "ZoneIdFilter for route53"
  type        = string
}

variable "dns_zone" {
  description = "DNS zone for cert-manager"
  type        = string
  default     = "meteogate.eu"
}

variable "vault_anti-affinity" {
  description = "Do you want to use Vault anti-affinity"
  type        = bool
  default     = true
}

variable "install_dev-portal" {
  description = "Should Dev-portal be installed"
  type        = bool
  default     = false
}

variable "install_geoweb" {
  description = "Should Geoweb be installed"
  type        = bool
  default     = false
}
