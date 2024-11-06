# EWC

## Init
Initialize the Terraform project:
```bash
terraform init
```


> [!IMPORTANT] 
> The EWC part of Terraform code has to be run in two separate part for bootstrapping the Vault instances


## First

Run the ewc-vault-init module:
```bash
terraform apply -target module.ewc-vault-init
```
Provide the needed variables. The varialbe `var.vault_token` can be anything for the first run.

The expected output should look something like this.
All the vault pods should be ready after the initialization.
```txt
Outputs:

dev-portal_keycloak_secret = <sensitive>
load_balancer_ip = "192.168.1.1"
vault_pod_ready_statuses_after_init = [
  "True",
  "True",
  "True",
]
vault_pod_ready_statuses_before_init = [
  "False",
  "False",
  "False",
]
vault_root_token = <sensitive>
vault_unseal_keys = <sensitive>
```

> [!IMPORTANT] 
> Make sure to store `vault_root_token` `vault_unseal_keys` and `dev-portal_keycloak_secret` somewhere safe.

You can access sensitive values using commands:
```bash
terraform output vault_root_token
terraform output vault_unseal_keys
```

## Second
Run the rest of the Terraform code:
```bash
terraform apply
```
Expected output looks like this.
```txt
Outputs:

dev-portal_keycloak_secret = <sensitive>
load_balancer_ip = "185.254.220.56"
vault_pod_ready_statuses_after_init = [
  "True",
  "True",
  "True",
]
vault_pod_ready_statuses_before_init = [
  "True",
  "True",
  "True",
]
```

> [!IMPORTANT] 
> This time make sure to store `dev-portal_keycloak_secret` somewhere safe:
```bash
terraform output dev-portal_keycloak_secret
```
