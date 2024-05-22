variable "rancher_api_url" {
  type = string
}

variable "rancher_access_key" {
  type = string
}

variable "rancher_secret_key" {
  type = string
}

variable "rancher_cluster_id" {
  type = string
  
}

variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}

