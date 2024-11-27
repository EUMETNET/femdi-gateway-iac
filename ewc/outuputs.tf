output "load_balancer_ip" {
  description = "Ip of load balancer created by nginx-ingress-controller"
  value       = module.ewc-vault-init.load_balancer_ip
}

output "vault_pod_ready_statuses_before_init" {
  description = "Vault cluster status before running init. If this array is true you should have unseal and root token in a previus run"
  value       = module.ewc-vault-init.vault_pod_ready_statuses_before_init

}

output "vault_unseal_keys" {
  description = "Keys for vault unsealing. Store somewhere safe. If empty Vault already initialized."
  value       = module.ewc-vault-init.vault_unseal_keys
  sensitive   = true
}

output "vault_root_token" {
  description = "Root token for vault. Store somewhere safe. If empty Vault already initialized."
  value       = module.ewc-vault-init.vault_root_token
  sensitive   = true
}

output "vault_pod_ready_statuses_after_init" {
  description = "Vault cluster status ater running init. Should be true."
  value       = module.ewc-vault-init.vault_pod_ready_statuses_after_init
}

output "dev-portal_keycloak_secret" {
  description = "Dev-portal's secret to authenticate with Keycloak"
  value       = module.dev-portal-init.dev-portal_keycloak_secret
  sensitive   = true
}

