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

variable "devportal-domain" {
  description = "Restrict Admin API Access by IP"
  type        = string
}

variable "apisix_backup_bucket_base_path" {
  description = "AWS S3 bucket base path for APISIX backup files"
  type        = string
  default     = "dev-rodeo-backups/ewc/apisix/"
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
