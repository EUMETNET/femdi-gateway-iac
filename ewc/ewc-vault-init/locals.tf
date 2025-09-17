/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
  ##############################################################
  # Cert-manager
  ##############################################################
  # cert_manager_email:       Email address used for cert-manager registrations and recovery contact.

  cert_manager_email = data.aws_ssm_parameter.cert_manager_email.value

  ##############################################################
  # Vault
  ##############################################################
  # vault_replica_count:      Number of Vault replicas to deploy.
  # vault_anti_affinity:      Whether to enable anti-affinity for Vault pods to spread them across nodes.

  vault_replica_count = tonumber(data.aws_ssm_parameter.vault_replica_count.value)

  vault_anti_affinity = lower(data.aws_ssm_parameter.vault_anti_affinity.value) == "true" ? true : false
}
