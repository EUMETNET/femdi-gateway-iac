##############################################################
# Dev Portal
##############################################################

data "aws_ssm_parameter" "dev_portal_registry_password" {
  name            = "/dev_portal/registry_password"
  with_decryption = true
}

data "aws_ssm_parameter" "cluster_names" {
  name = "/cluster_names"
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
  name        = "/keycloak/admin_password"
  description = "Admin password for Keycloak"
  type        = "SecureString"
  value       = random_password.keycloak_admin_password.result
}

data "aws_ssm_parameter" "keycloak_github_idp_client_secret" {
  name            = "/keycloak/github_idp_client_secret"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_google_idp_client_secret" {
  name            = "/keycloak/google_idp_client_secret"
  with_decryption = true
}

data "aws_ssm_parameter" "keycloak_replica_count" {
  name = "/keycloak/replica_count"
}
