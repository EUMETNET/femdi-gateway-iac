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

variable "geoweb_subdomain" {
  description = "subdomain where Geoweb will be hosted"
  type        = string
}

variable "keycloak_subdomain" {
  description = "subdomain where keycloak will be hosted"
  type        = string
}

variable "keycloak_realm_name" {
  description = "Name of the keycloak realm"
  type        = string
}