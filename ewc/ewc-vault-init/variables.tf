variable "rancher_api_url" {
  description = "Rancher instance URL"
  type        = string
}

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

variable "rancher_cluster_id" {
  description = "ID of your Rancher cluster"
  type        = string

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

variable "apisix_subdomain" {
  description = "Subdomain for APISIX"
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

variable "route53_hosted_zone_ids" {
  description = "List of Route 53 hosted zone IDs"
  type        = list(string)
}

variable "hosted_zone_names" {
  description = "List of Route 53 hosted zone names"
  type        = list(string)
}

variable "dns_zone" {
  description = "DNS zone for cert-manager"
  type        = string
}

variable "vault_project_id" {
  description = "Rancher project where vault namespace will be created"
  type        = string
}

variable "vault_subdomain" {
  description = "subdomain where vault will be hosted"
  type        = string
  default     = "vault"
}

variable "vault_key_treshold" {
  description = "Treshold to unseal Vault"
  type        = number
  default     = 3
}


