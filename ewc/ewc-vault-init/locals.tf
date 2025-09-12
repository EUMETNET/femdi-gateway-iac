/*
    Map SSM parameters to locals to make it one point of truth:
        - easier management if changing param name or changing provider from SSM to other
        - avoid repeating data source calls in multiple places
*/

locals {
  cert_manager_email = data.aws_ssm_parameter.cert_manager_email.value

  vault_replica_count = tonumber(data.aws_ssm_parameter.vault_replica_count.value)
}