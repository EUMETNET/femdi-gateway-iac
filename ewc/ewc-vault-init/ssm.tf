##############################################################
# Cert-manager
##############################################################

data "aws_ssm_parameter" "cert_manager_email" {
  name = "/cert_manager/email_address"
}

##############################################################
# Vault
##############################################################

data "aws_ssm_parameter" "vault_replica_count" {
  name = "/vault/replica_count"
}

data "aws_ssm_parameter" "vault_anti_affinity" {
  name = "/${var.cluster_name}/vault/anti_affinity"
}
