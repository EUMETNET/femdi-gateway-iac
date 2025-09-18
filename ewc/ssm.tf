##############################################################
# Cluster
##############################################################

data "aws_ssm_parameter" "rancher_api_url" {
  name = "/${var.cluster_name}/rancher_api_url"
}

data "aws_ssm_parameter" "rancher_cluster_id" {
  name = "/${var.cluster_name}/rancher_cluster_id"
}

##############################################################
# Global AWS
##############################################################

data "aws_ssm_parameter" "backups_aws_access_key_id" {
  name            = "/iam/backups/access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "backups_aws_secret_access_key" {
  name            = "/iam/backups/secret_access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "backups_bucket_name" {
  name = "/s3/backups/bucket_name"
}

data "aws_ssm_parameter" "certmgr_extdns_aws_access_key" {
  name            = "/iam/certmgr_extdns/access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "certmgr_extdns_aws_secret_access_key" {
  name            = "/iam/certmgr_extdns/secret_access_key"
  with_decryption = true
}

data "aws_ssm_parameter" "route53_hosted_zone_id" {
  name = "/route53/hosted_zone_id/${var.dns_zone}"
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
  name        = "/${var.cluster_name}/apisix/reader_api_key"
  description = "Reader API key to control access to the APISIX Admin API endpoints"
  type        = "SecureString"
  value       = random_password.apisix_admin_reader_api_key.result
}

# Fetch parameters

data "aws_ssm_parameter" "apisix_subdomain" {
  name = "/apisix/subdomain"
}

data "aws_ssm_parameter" "apisix_admin_api_ip_list" {
  name = "/${var.cluster_name}/apisix/admin_api_ip_list"
}

data "aws_ssm_parameter" "ingress_nginx_private_subnets" {
  name = "/${var.cluster_name}/apisix/ingress_nginx_private_subnets"
}

data "aws_ssm_parameter" "apisix_replica_count" {
  name = "/apisix/replica_count"
}

data "aws_ssm_parameter" "apisix_etcd_replica_count" {
  name = "/apisix/etcd/replica_count"
}

##############################################################
# Dev Portal
##############################################################

data "aws_ssm_parameter" "dev_portal_subdomain" {
  name = "/dev_portal/subdomain"
}

data "aws_ssm_parameter" "install_dev_portal" {
  name = "/${var.cluster_name}/install_dev_portal"
}

##############################################################
# Keycloak
##############################################################

data "aws_ssm_parameter" "keycloak_subdomain" {
  name = "/keycloak/subdomain"
}

data "aws_ssm_parameter" "keycloak_realm_name" {
  name = "/keycloak/realm_name"
}

##############################################################
# Vault
##############################################################

data "aws_ssm_parameter" "vault_root_token" {
  name            = "/${var.cluster_name}/vault/root_token"
  with_decryption = true
}

data "aws_ssm_parameter" "vault_subdomain" {
  name = "/vault/subdomain"
}

data "aws_ssm_parameter" "vault_key_treshold" {
  name = "/vault/key_threshold"
}

##############################################################
# Geoweb
##############################################################

data "aws_ssm_parameter" "geoweb_subdomain" {
  name = "/geoweb/subdomain"
}

data "aws_ssm_parameter" "install_geoweb" {
  name = "/${var.cluster_name}/install_geoweb"
}

##############################################################
# Alert manager
##############################################################

data "aws_ssm_parameter" "alert_email_sender" {
  name = "/alert_manager/email_sender"
}

data "aws_ssm_parameter" "alert_email_recipients" {
  name = "/alert_manager/email_recipients"
}

data "aws_ssm_parameter" "alert_smtp_auth_password" {
  name            = "/alert_manager/smtp_auth_password"
  with_decryption = true
}

data "aws_ssm_parameter" "alert_smtp_auth_username" {
  name = "/alert_manager/smtp_auth_username"
}

data "aws_ssm_parameter" "alert_smtp_host" {
  name = "/alert_manager/smtp_host"
}
