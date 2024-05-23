variable "rancher_api_url" {
  description = "Rancher instance URL"
  type = string
}

variable "rancher_access_key" {
  description = "Rancher instance access key"
  type = string
  sensitive = true
}

variable "rancher_secret_key" {
  description = "Rancher instance secret key"
  type = string
  sensitive = true
}

variable "rancher_cluster_id" {
  description = "Name of your Rancher cluster"
  type = string
  
}

variable "kubeconfig_path" {
  description = "Path to your kubeconfig"
  type    = string
  default = "~/.kube/config"
}


variable "route53_access_key" {
  description = "AWS access key for route53"
  type    = string
  sensitive = true
}

variable "route53_secret_key" {
  description = "AWS secret key for route53"
  type    = string
  sensitive = true
}

variable "route53_zone_id_filter" {
  description = "ZoneIdFilter for route53"
  type    = string
  sensitive = true
}

variable "dns_zone" {
  description = "DNS zone for cert-manager"
  type    = string
  default = "eumetnet-femdi.eumetsat.ewcloud.host"
}

variable "email_cert_manager" {
  description = "email for Let's encrypt cert-manager"
  type    = string
  default = "eumetnet-femdi.eumetsat.ewcloud.host"
}
