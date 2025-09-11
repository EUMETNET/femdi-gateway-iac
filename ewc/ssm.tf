##############################################################
# Cluster
##############################################################

data "aws_ssm_parameter" "rancher_api_url" {
  provider = aws.fmi
  name     = "/${var.cluster_name}/rancher_api_url"
}

data "aws_ssm_parameter" "rancher_token" {
  provider        = aws.fmi
  name            = "/${var.cluster_name}/rancher_token"
  with_decryption = true
}

data "aws_ssm_parameter" "rancher_cluster_id" {
  provider = aws.fmi
  name     = "/${var.cluster_name}/rancher_cluster_id"
}

# TODO we need a way to pass the file to kubernetes provider
data "aws_ssm_parameter" "kubeconfig_file" {
  provider        = aws.fmi
  name            = "/${var.cluster_name}/kubeconfig_file"
  with_decryption = true
}

##############################################################
# Cert-manager
##############################################################

data "aws_ssm_parameter" "cert_manager_email" {
  provider = aws.fmi
  name     = "/cert_manager/email_address"
}

##############################################################
# APISIX
##############################################################

# Create parameters

resource "random_password" "apisix_admin_api_key" {
  length  = 32
  special = true
}

resource "aws_ssm_parameter" "apisix_admin_api_key" {
  provider    = aws.fmi
  name        = "/${var.cluster_name}/apisix/admin_api_key"
  description = "Admin API key to control access to the APISIX Admin API endpoints"
  type        = "SecureString"
  value       = random_password.apisix_admin_api_key.result
}

resource "random_password" "apisix_admin_reader_api_key" {
  length  = 32
  special = true
}

resource "aws_ssm_parameter" "apisix_admin_reader_api_key" {
  provider    = aws.fmi
  name        = "/${var.cluster_name}/apisix/reader_api_key"
  description = "Reader API key to control access to the APISIX Admin API endpoints"
  type        = "SecureString"
  value       = random_password.apisix_admin_reader_api_key.result
}

# Fetch parameters

data "aws_ssm_parameter" "apisix_subdomain" {
  provider = aws.fmi
  name     = "/apisix/subdomain"
}

data "aws_ssm_parameter" "apisix_admin_api_ip_list" {
  provider = aws.fmi
  name     = "/${var.cluster_name}/apisix/admin_api_ip_list"
}

data "aws_ssm_parameter" "ingress_nginx_private_subnets" {
  provider = aws.fmi
  name     = "/${var.cluster_name}/apisix/ingress_nginx_private_subnets"
}

##############################################################
# Alert manager
##############################################################

data "aws_ssm_parameter" "alert_email_sender" {
  provider = aws.fmi
  name     = "/alert_manager/email_sender"
}

data "aws_ssm_parameter" "alert_email_recipients" {
  provider = aws.fmi
  name     = "/alert_manager/email_recipients"
}

data "aws_ssm_parameter" "alert_smtp_auth_password" {
  provider        = aws.fmi
  name            = "/alert_manager/smtp_auth_password"
  with_decryption = true
}

data "aws_ssm_parameter" "alert_smtp_auth_username" {
  provider = aws.fmi
  name     = "/alert_manager/smtp_auth_username"
}

data "aws_ssm_parameter" "alert_smtp_host" {
  provider = aws.fmi
  name     = "/alert_manager/smtp_host"
}
