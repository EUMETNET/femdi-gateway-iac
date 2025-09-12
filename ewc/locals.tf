/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
  rancher_api_url    = data.aws_ssm_parameter.rancher_api_url.value
  rancher_cluster_id = data.aws_ssm_parameter.rancher_cluster_id.value

  backup_aws_access_key_id     = data.aws_ssm_parameter.backups_aws_access_key_id.value
  backup_aws_secret_access_key = data.aws_ssm_parameter.backups_aws_secret_access_key.value
  backup_bucket_name           = data.aws_ssm_parameter.backups_bucket_name.value

  apisix_admin_api_key          = aws_ssm_parameter.apisix_admin_api_key.value
  apisix_admin_reader_api_key   = aws_ssm_parameter.apisix_admin_reader_api_key.value
  apisix_admin_api_ip_list      = data.aws_ssm_parameter.apisix_admin_api_ip_list.value
  apisix_subdomain              = data.aws_ssm_parameter.apisix_subdomain.value
  ingress_nginx_private_subnets = data.aws_ssm_parameter.ingress_nginx_private_subnets.value

  dev_portal_subdomain = data.aws_ssm_parameter.dev_portal_subdomain.value

  keycloak_subdomain = data.aws_ssm_parameter.keycloak_subdomain.value

  vault_token     = data.aws_ssm_parameter.vault_root_token.value
  vault_subdomain = data.aws_ssm_parameter.vault_subdomain.value

  alert_manager_email_sender       = data.aws_ssm_parameter.alert_email_sender.value
  alert_manager_email_recipients   = data.aws_ssm_parameter.alert_email_recipients.value
  alert_manager_smtp_auth_password = data.aws_ssm_parameter.alert_smtp_auth_password.value
  alert_manager_smtp_auth_username = data.aws_ssm_parameter.alert_smtp_auth_username.value
  alert_manager_smtp_host          = data.aws_ssm_parameter.alert_smtp_host.value
}