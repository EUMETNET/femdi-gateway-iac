variable "rancher_api_url" {
  description = "Rancher instance URL"
  type        = string
}

variable "rancher_token" {
  description = "Rancher instance access key"
  type        = string
  sensitive   = true
}


variable "rancher_cluster_id" {
  description = "ID of your Rancher cluster"
  type        = string

}

variable "kubeconfig_path" {
  description = "Path to your kubeconfig"
  type        = string
  default     = "~/.kube/config"
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
  default     = "eumetnet-femdi.eumetsat.ewcloud.host"
}

variable "email_cert_manager" {
  description = "email for Let's encrypt cert-manager"
  type        = string
}

variable "apisix_admin" {
  description = "Admin API key to control access to the APISIX Admin API endpoints"
  type        = string
  sensitive   = true
}

variable "apisix_reader" {
  description = "Reader API key to control access to the APISIX Admin API endpoints"
  type        = string
  sensitive   = true
}

variable "apisix_subdomain" {
  description = "subdomain where apisix will be hosted"
  type        = string
  default     = "gateway"
}

variable "apisix_ip_list" {
  description = "Restrict Admin API Access by IP CIDR"
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition = alltrue([
      for i in var.apisix_ip_list:
      can(cidrnetmask(i))
    ])
    error_message = "Not a valid list of CIDR-blocks"
  }
}

variable "vault_subdomain" {
  description = "subdomain where apisix will be hosted"
  type        = string
  default     = "vault"
}

variable "vault_s3_access_key" {
  description = "subdomain where apisix will be hosted"
  type        = string
  sensitive   = true
}

variable "vault_s3_secret_key" {
  description = "subdomain where apisix will be hosted"
  type        = string
  sensitive   = true
}

variable "vault_s3_bucket" {
  description = "subdomain where apisix will be hosted"
  type        = string
  sensitive   = true
}

variable "vault_s3_region" {
  description = "subdomain where apisix will be hosted"
  type        = string
  default = "eu-north-1"
}

