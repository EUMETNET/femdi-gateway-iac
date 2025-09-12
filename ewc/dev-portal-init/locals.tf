/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
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

  keycloak_admin_password = aws_ssm_parameter.keycloak_admin_password.value
  keycloak_replica_count  = tonumber(data.aws_ssm_parameter.keycloak_replica_count.value)

  google_idp_client_secret = data.aws_ssm_parameter.keycloak_google_idp_client_secret.value
  github_idp_client_secret = data.aws_ssm_parameter.keycloak_github_idp_client_secret.value
}
