##############################################################
# Cert-manager
##############################################################

data "aws_ssm_parameter" "cert_manager_email" {
  name = "/cert_manager/email_address"
}

data "aws_ssm_parameter" "vault_replica_count" {
  name = "/vault/replica_count"
}
