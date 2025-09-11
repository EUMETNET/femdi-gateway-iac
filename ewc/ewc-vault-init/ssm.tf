##############################################################
# Cert-manager
##############################################################

data "aws_ssm_parameter" "cert_manager_email" {
  name = "/cert_manager/email_address"
}

locals {
  cert_manager_email = data.aws_ssm_parameter.cert_manager_email.value
}