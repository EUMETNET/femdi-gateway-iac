variable "kubeconfig_path" {
  description = "Path to your kubeconfig"
  type        = string
  validation {
    condition     = fileexists(var.kubeconfig_path)
    error_message = "The specified kubeconfig file does not exist."
  }
}

variable "dns_zone" {
  description = "DNS zone for cert-manager"
  type        = string
}

variable "cluster_issuer" {
  description = "Certrificate issuer for the cluster"
}

variable "load_balancer_ip" {
  description = "Load balancer's public IP"
  type        = string
}

variable "rancher_project_id" {
  description = "id for Rancher project use to host the namespaces"
  type        = string
}

variable "keycloak_admin_password" {
  description = "Password for keycloak admin"
  type        = string
  sensitive   = true
}

variable "keycloak_subdomain" {
  description = "subdomain where keycloak will be hosted"
  type        = string
}

variable "keycloak_replicas" {
  description = "Amount of keycloak replicas"
  type        = number
}

variable "dev-portal_subdomain" {
  description = "subdomain where devportal will be hosted"
  type        = string
}

variable "dev-portal_registry_password" {
  description = "Container registry password for dev-portal"
  type        = string
  sensitive   = true
}

variable "dev-portal_vault_token" {
  description = "Dev-portal's token for Vault"
  type        = string
  sensitive   = true
}

variable "apisix_subdomain" {
  description = "Subdomain for Apisix"
  type        = string
}

variable "apisix_global_subdomain" {
  description = "Unified subdomain to access any APISIX gateway instance"
  type        = string
}

variable "apisix_admin" {
  description = "Admin credentials for Apisix"
  type        = string
  sensitive   = true
}

variable "apisix_helm_release_name" {
  description = "Name of the Helm release for Apisix"
  type        = string
}

variable "apisix_namespace_name" {
  description = "Name of the namespace where Apisix is running"
  type        = string
}

variable "apisix_additional_instances" {
  description = "Config for additional Apisix instances"
  type = list(object({
    name          = string
    admin_url     = string
    admin_api_key = string
  }))
  default = []
}

variable "vault_additional_instances" {
  description = "Config for additional Apisix instances"
  type = list(object({
    name  = string
    token = string
    url   = string
  }))
  default = []
}

variable "vault_helm_release_name" {
  description = "Name of the Helm release for Vault"
  type        = string
}

variable "vault_namespace_name" {
  description = "Name of the namespace where Vault is running"
  type        = string
}

variable "vault_mount_kv_base_path" {
  description = "Base path for KV secrets engine in Vault"
  type        = string
}

variable "google_idp_client_secret" {
  description = "Secret to use Google idp"
  type        = string
  sensitive   = true
}

variable "github_idp_client_secret" {
  description = "Secret to use Github idp"
  type        = string
  sensitive   = true
}

variable "s3_bucket_access_key" {
  description = "AWS access key for S3 bucket for backups"
  type        = string
  sensitive   = true
}

variable "s3_bucket_secret_key" {
  description = "AWS secret key for S3 bucket for backups"
  type        = string
  sensitive   = true
}

variable "backup_bucket_base_path" {
  description = "AWS S3 bucket base path for Keycloak backup files"
  type        = string
}
