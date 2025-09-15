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
# Global AWS
##############################################################

data "aws_ssm_parameter" "backups_aws_access_key_id" {
  provider        = aws.fmi
  name            = "/iam/backups/access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "backups_aws_secret_access_key" {
  provider        = aws.fmi
  name            = "/iam/backups/secret_access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "backups_bucket_name" {
  provider = aws.fmi
  name     = "/s3/backups/bucket_name"
}

data "aws_ssm_parameter" "certmgr_extdns_aws_access_key" {
  provider        = aws.fmi
  name            = "/iam/certmgr_extdns/access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "certmgr_extdns_aws_secret_access_key" {
  provider        = aws.fmi
  name            = "/iam/certmgr_extdns/secret_access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "route53_hosted_zone_id" {
  provider = aws.fmi
  name     = "/route53/hosted_zone_id/${var.dns_zone}"
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

data "aws_ssm_parameter" "apisix_replica_count" {
  provider = aws.fmi
  name     = "/apisix/replica_count"
}

data "aws_ssm_parameter" "apisix_etcd_replica_count" {
  provider = aws.fmi
  name     = "/apisix/etcd/replica_count"
}

##############################################################
# Dev Portal
##############################################################

data "aws_ssm_parameter" "dev_portal_subdomain" {
  provider = aws.fmi
  name     = "/dev_portal/subdomain"
}

##############################################################
# Keycloak
##############################################################

data "aws_ssm_parameter" "keycloak_subdomain" {
  provider = aws.fmi
  name     = "/keycloak/subdomain"
}

data "aws_ssm_parameter" "keycloak_realm_name" {
  provider = aws.fmi
  name     = "/keycloak/realm_name"
}

##############################################################
# Vault
##############################################################

data "aws_ssm_parameter" "vault_root_token" {
  provider        = aws.fmi
  name            = "/vault/${var.cluster_name}/root_token"
  with_decryption = true
}

data "aws_ssm_parameter" "vault_subdomain" {
  provider = aws.fmi
  name     = "/vault/subdomain"
}

data "aws_ssm_parameter" "vault_key_treshold" {
  provider = aws.fmi
  name     = "/vault/key_threshold"
}

##############################################################
# Geoweb
##############################################################

data "aws_ssm_parameter" "geoweb_subdomain" {
  provider = aws.fmi
  name     = "/geoweb/subdomain"
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
