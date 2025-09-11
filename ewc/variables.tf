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

variable "manage_global_dns_records" {
  description = "Should this cluster manage global DNS records"
  type        = bool
  default     = false
}

variable "observations_ip" {
  description = "IP address for observations A record"
  type        = string
}

variable "radar_ip" {
  description = "IP address for radar A record"
  type        = string
}

variable "root_ip" {
  description = "IP address for root A record in hosted zone"
  type        = string
}

variable "apisix_replicas" {
  description = "Amount of minimum replicas for APISIX"
  type        = number
  default     = 1
}

variable "apisix_etcd_replicas" {
  description = "Amount of etcd replicas for APISIX"
  type        = number
  default     = 3
}

variable "keycloak_replicas" {
  description = "Amount of keycloak replicas"
  type        = number
  default     = 1
}

variable "keycloak_realm_name" {
  description = "Name of the keycloak realm"
  type        = string
  default     = "meteogate"
}

variable "vault_replicas" {
  description = "Amount of vault replicas"
  type        = number
  default     = 3
}

variable "vault_anti-affinity" {
  description = "Do you want to use Vault anti-affinity"
  type        = bool
  default     = true
}

variable "vault_key_treshold" {
  description = "Treshold to unseal Vault"
  type        = number
  default     = 3
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

variable "geoweb_subdomain" {
  description = "subdomain where Geoweb will be hosted"
  type        = string
  default     = "explorer"
}
