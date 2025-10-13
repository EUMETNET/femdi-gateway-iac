/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
  ##############################################################
  # SSM parameters
  ##############################################################
  ##############################################################
  #   Dev Portal
  ##############################################################

  # dev-portal_registry_password:     Password for accessing the private container registry hosting the Dev Portal image.
  # Following are needed by Dev Portal to access other clusters APISIX and Vault:
  # external_cluster_names:           Set of names of other clusters (not this one) in the multi-cluster setup.
  # external_apisix_admin_api_keys:   Map of APISIX admin API keys for other clusters in the multi-cluster setup.
  # external_vault_tokens:            Map of Vault root tokens for other clusters in the multi-cluster setup.

  dev_portal_keycloak_secret   = data.aws_ssm_parameter.dev_portal_keycloak_secret.value
  dev_portal_registry_password = data.aws_ssm_parameter.dev_portal_registry_password.value
  external_cluster_names = toset([
    for name in split(",", nonsensitive(data.aws_ssm_parameter.cluster_names.value)) :
    name if name != var.cluster_name
  ])
  external_apisix_admin_api_keys = {
    for cluster_name, param in data.aws_ssm_parameter.external_apisix_admin_api_keys :
    cluster_name => param.value
  }
  external_vault_tokens = {
    for cluster_name, param in data.aws_ssm_parameter.external_vault_tokens :
    cluster_name => param.value
  }

  ##############################################################
  #   Keycloak
  ##############################################################
  # keycloak_admin_password:       Admin password for Keycloak.
  # keycloak_replica_count:       Number of Keycloak replicas to deploy.
  # google_idp_client_secret:      OAuth2 client secret for Google identity provider in Keycloak.
  # github_idp_client_secret:      OAuth2 client secret for GitHub identity provider in Keycloak.

  keycloak_admin_password = aws_ssm_parameter.keycloak_admin_password.value
  keycloak_replica_count  = tonumber(data.aws_ssm_parameter.keycloak_replica_count.value)

  google_idp_client_secret = data.aws_ssm_parameter.keycloak_google_idp_client_secret.value
  github_idp_client_secret = data.aws_ssm_parameter.keycloak_github_idp_client_secret.value

  ##############################################################
  # Other locals
  ##############################################################
  alternative_hosted_zone_names = [for name in var.hosted_zone_names : name if name != var.dns_zone]
}
