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
>
> If the Vault is recreated for a data restore operation, do not delete the previous `vault_unseal_keys`. Continue using the old unseal keys and ignore the new ones. The new `vault_root_token` is needed. For more details, see the [Vault Restore](#vault-restore) section.

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

## Disaster Recovery

The disaster recovery plan includes backing up application databases and logical data, and restoring them from snapshot files. The backup and restore processes are performed using database-specific tools like `pg_dump` and `pg_restore`.

### Backups

Each application (Keycloak, APISIX, Vault) has a dedicated Cron job for backups. The backup schedule can be adjusted using Terraform if needed. Currently, backups are saved to an AWS S3 bucket. If there is no need to store files older than a certain number of days, bucket retention policies can be used to manage this.

### Restore

Each application has dedicated job(s) to restore data from snapshots. These jobs are invoked with independent commands, but the job templates are managed within Terraform.

**Note:** Ensure that the Terraform state and the actual cluster state are aligned before running restore jobs to avoid potential issues.

#### Keycloak Restore

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file
export SNAPSHOT_NAME="specific_snapshot.db" # Optionally provide a specific snapshot name if you need to restore a snapshot other than the latest one

# Create the restore job and capture the job name
JOB_NAME=$(kubectl get configmap keycloak-restore-backup -n keycloak -o jsonpath='{.data.job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the job
kubectl logs -f $JOB_NAME -n keycloak

# Optionally, delete the job and its resources after completion
kubectl delete $JOB_NAME -n keycloak
```

#### Vault Restore

**Note:** Vault restore requires the UNSEAL_KEYS that were in use when the backup snapshot was taken. The VAULT_TOKEN is the latest root token that was created and used. If the Vault cluster becomes unresponsive or is completely wiped out, the existing cluster might need to be removed and a new one initialized. The new cluster will have new tokens and unseal keys. To access the cluster, the new token is needed, but unsealing the cluster requires the unseal keys used by the data in the snapshot.

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file
export SNAPSHOT_NAME="specific_snapshot.db" # Optionally provide a specific snapshot name if you need to restore a snapshot other than the latest one
export UNSEAL_KEYS= # Provide the unseal keys
export VAULT_TOKEN= # Provide the Vault token

# Create the restore job and capture the job name
JOB_NAME=$(kubectl get configmap vault-restore-backup -n vault -o jsonpath='{.data.job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the job
kubectl logs -f $JOB_NAME -n vault

# Optionally, delete the job and its resources after completion
kubectl delete $JOB_NAME -n vault
```

#### APISIX Restore

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file
export SNAPSHOT_NAME="specific_snapshot.db" # Optionally provide a specific snapshot name if you need to restore a snapshot other than the latest one

# Create the pre-restore job and capture the job name
PRE_JOB_NAME=$(kubectl get configmap apisix-restore-backup -n apisix -o jsonpath='{.data.pre-job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the pre-restore job
kubectl logs -f $PRE_JOB_NAME -n apisix

# Optionally, delete the pre-restore job and its resources after completion
kubectl delete $PRE_JOB_NAME -n apisix

# Create the main restore job and capture the job name
MAIN_JOB_NAME=$(kubectl get configmap apisix-restore-backup -n apisix -o jsonpath='{.data.job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the main restore job
kubectl logs -f $MAIN_JOB_NAME -n apisix

# Optionally, delete the main restore job and its resources after completion
kubectl delete $MAIN_JOB_NAME -n apisix

# Create the post-restore job and capture the job name
POST_JOB_NAME=$(kubectl get configmap apisix-restore-backup -n apisix -o jsonpath='{.data.post-job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the post-restore job
kubectl logs -f $POST_JOB_NAME -n apisix

# Optionally, delete the post-restore job and its resources after completion
kubectl delete $POST_JOB_NAME -n apisix
```