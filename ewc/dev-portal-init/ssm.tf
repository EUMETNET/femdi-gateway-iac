##############################################################
# Dev Portal
##############################################################

resource "random_password" "keycloak-dev-portal-secret" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "dev_portal_keycloak_secret" {
  name        = "/${var.cluster_name}/dev_portal/keycloak_secret"
  description = "Dev Portal secret for accessing Keycloak"
  type        = "SecureString"
  value       = random_password.keycloak-dev-portal-secret.result
}

data "aws_ssm_parameter" "dev_portal_registry_password" {
  name            = "/dev_portal/registry_password"
  with_decryption = true
}

data "aws_ssm_parameter" "cluster_names" {
  name = "/${var.cluster_name}/dev_portal/external_cluster_names"
}

data "aws_ssm_parameter" "external_apisix_admin_api_keys" {
  for_each = local.external_cluster_names
  name     = "/${each.key}/apisix/admin_api_key"
}

data "aws_ssm_parameter" "external_vault_tokens" {
  for_each = local.external_cluster_names
  name     = "/${each.key}/vault/root_token"
}


##############################################################
# Keycloak
##############################################################

resource "random_password" "keycloak_admin_password" {
  length  = 32
  special = true
}

resource "aws_ssm_parameter" "keycloak_admin_password" {
  name        = "/${var.cluster_name}/keycloak/admin_password"
  description = "Admin password for Keycloak"
  type        = "SecureString"
  value       = random_password.keycloak_admin_password.result
}

data "aws_ssm_parameter" "keycloak_github_idp_client_id" {
  name            = "/${var.cluster_name}/keycloak/github_idp_client_id"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_github_idp_client_secret" {
  name            = "/${var.cluster_name}/keycloak/github_idp_client_secret"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_google_idp_client_id" {
  name            = "/${var.cluster_name}/keycloak/google_idp_client_id"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_google_idp_client_secret" {
  name            = "/${var.cluster_name}/keycloak/google_idp_client_secret"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_replica_count" {
  name = "/keycloak/replica_count"
}
