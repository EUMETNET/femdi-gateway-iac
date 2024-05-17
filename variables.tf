variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-north-1"
}

variable "main-region" {
  type    = string
  default = "eu-north-1"
}

variable "env_name" {
  description = "Environment name"
  type        = string
  default     = "rodeo-dev"
}

variable "cluster_name" {
  type    = string
  default = "terra-apisix"
}

variable "certificateARN" {
  description = "AWS Certificate Manager certificate ARN, used by the NLB"
  type        = string
}

variable "apisixAdmin" {
  description = "Admin API key to control access to the APISIX Admin API endpoints"
  type        = string
}

variable "apisixReader" {
  description = "Reader API key to control access to the APISIX Admin API endpoints"
  type        = string
}

variable "apisixIpList" {
  description = "Restrict Admin API Access by IP"
  type        = string
}