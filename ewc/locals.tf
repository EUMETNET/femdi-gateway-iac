/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
  ##############################################################
  # Cluster
  ##############################################################

  # rancher_api_url      : The URL endpoint for accessing the Rancher API dashboard.
  # rancher_cluster_id   : The unique identifier for the Rancher-managed cluster.

  rancher_api_url    = data.aws_ssm_parameter.rancher_api_url.value
  rancher_cluster_id = data.aws_ssm_parameter.rancher_cluster_id.value

  ##############################################################
  # Global AWS
  ##############################################################

  # backup_aws_access_key_id      : AWS access key ID for the backup/restore IAM user.
  # backup_aws_secret_access_key  : AWS secret access key for the backup/restore IAM user.
  # backup_bucket_name            : Name of the S3 bucket used for storing/restoring backups.
  # route53_aws_access_key        : AWS access key ID for the Route 53
  # route53_aws_secret_access_key : AWS secret access key for the Route 53
  # hosted_zone_names             : List of Route 53 hosted zone names.
  # dns_zone                      : The primary Route 53 hosted zone name.
  # alternative_hosted_zone_names : List of alternative Route 53 hosted zone names excluding the main dns zone.
  # route53_hosted_zone_ids       : The IDs of the Route 53 hosted zones.

  backup_aws_access_key_id      = data.aws_ssm_parameter.backups_aws_access_key_id.value
  backup_aws_secret_access_key  = data.aws_ssm_parameter.backups_aws_secret_access_key.value
  backup_bucket_name            = data.aws_ssm_parameter.backups_bucket_name.value
  route53_aws_access_key        = data.aws_ssm_parameter.certmgr_extdns_aws_access_key.value
  route53_aws_secret_access_key = data.aws_ssm_parameter.certmgr_extdns_aws_secret_access_key.value
  hosted_zone_names             = split(",", data.aws_ssm_parameter.hosted_zone_names.value)
  dns_zone                      = data.aws_ssm_parameter.route53_main_hosted_zone.value
  alternative_hosted_zone_names = [for name in local.hosted_zone_names : name if name != local.dns_zone]
  route53_hosted_zone_ids       = toset([for v in data.aws_ssm_parameter.route53_hosted_zone_ids : v.value])

  ##############################################################
  # APISIX
  ##############################################################

  # apisix_subdomain:                 Specifies the subdomain to be used for APISIX gateway.
  #                                   NOTE: Service specific domain also contains the cluster name (<service-subdomain>.<cluster_name>.domain.com). 
  # apisix_admin_api_key:             Admin authentication token for APISIX management operations.
  # apisix_admin_reader_api_key:      Reader authentication token for APISIX read-only operations.
  # apisix_admin_api_ip_list:         List of allowed IP ranges for accessing APISIX Admin API.
  # ingress_nginx_private_subnets:    Specifies the private subnet(s) used by the cluster's ingress-nginx controller. Determines the trusted addresses for real-ip plugin.
  #                                   For now queried with kubectl describe svc ingress-nginx-controller -n kube-system
  #                                   and determined from the Endpoints
  # apisix_replica_count:             Number of APISIX replicas to deploy.
  # apisix_etcd_replica_count:        Number of etcd replicas to deploy for APISIX.

  apisix_subdomain              = data.aws_ssm_parameter.apisix_subdomain.value
  apisix_admin_api_key          = aws_ssm_parameter.apisix_admin_api_key.value
  apisix_admin_reader_api_key   = aws_ssm_parameter.apisix_admin_reader_api_key.value
  apisix_admin_api_ip_list      = data.aws_ssm_parameter.apisix_admin_api_ip_list.value
  ingress_nginx_private_subnets = data.aws_ssm_parameter.ingress_nginx_private_subnets.value
  apisix_replica_count          = tonumber(data.aws_ssm_parameter.apisix_replica_count.value)
  apisix_etcd_replica_count     = tonumber(data.aws_ssm_parameter.apisix_etcd_replica_count.value)

  ##############################################################
  # Dev Portal & Keycloak
  ##############################################################


  # install_dev-portal:            Whether to install the Dev Portal application.
  # dev-portal_subdomain:          Subdomain for accessing the Dev Portal.
  #                                NOTE: Service specific domain does NOT contain the cluster name (<service-subdomain>.domain.com) because this is global service.
  # keycloak_subdomain:            Subdomain for accessing Keycloak.
  #                                NOTE: Service specific domain does NOT contain the cluster name (<service-subdomain>.domain.com) because this is global service.
  # keycloak_realm_name:           Name of the Keycloak realm to be created/used.

  install_dev_portal   = lower(data.aws_ssm_parameter.install_dev_portal.value) == "true" ? true : false
  dev_portal_subdomain = data.aws_ssm_parameter.dev_portal_subdomain.value

  keycloak_subdomain  = data.aws_ssm_parameter.keycloak_subdomain.value
  keycloak_realm_name = data.aws_ssm_parameter.keycloak_realm_name.value

  ##############################################################
  # VAULT
  ##############################################################

  # vault_token:          Authentication token for accessing Vault generated by the ewc-vault-init module.
  # vault_subdomain:      Subdomain used to construct the Vault service endpoint.
  #                       Note: Service-specific domains include the cluster name in the format <service-subdomain>.<cluster_name>.domain.com.
  # vault_key_treshold:   Number of key shares required to unseal Vault.

  vault_token        = data.aws_ssm_parameter.vault_root_token.value
  vault_subdomain    = data.aws_ssm_parameter.vault_subdomain.value
  vault_key_treshold = tonumber(data.aws_ssm_parameter.vault_key_treshold.value)

  ##############################################################
  # Geoweb
  ##############################################################

  # geoweb_subdomain:   Subdomain for accessing Geoweb.
  #                     NOTE: Service specific domain does NOT contain the cluster name (<service-subdomain>.domain.com) because this is global service.
  # install_geoweb:     Whether to install the Geoweb application.


  geoweb_subdomain = data.aws_ssm_parameter.geoweb_subdomain.value
  install_geoweb   = lower(data.aws_ssm_parameter.install_geoweb.value) == "true" ? true : false

  ##############################################################
  # Alert manager
  ##############################################################

  # alert_email_sender:           The email address used as the sender for alert emails.
  # alert_email_recipients:       List of email addresses that will receive alert notifications.
  # alert_smtp_auth_password:     SMTP authentication password for the sender email account.
  # alert_smtp_auth_username:     SMTP authentication username (typically the sender email address).
  # alert_smtp_host:              SMTP server address and port used for sending emails.

  alert_manager_email_sender       = data.aws_ssm_parameter.alert_email_sender.value
  alert_manager_email_recipients   = data.aws_ssm_parameter.alert_email_recipients.value
  alert_manager_smtp_auth_password = data.aws_ssm_parameter.alert_smtp_auth_password.value
  alert_manager_smtp_auth_username = data.aws_ssm_parameter.alert_smtp_auth_username.value
  alert_manager_smtp_host          = data.aws_ssm_parameter.alert_smtp_host.value
}
