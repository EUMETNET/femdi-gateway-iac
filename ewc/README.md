# EWC

## TODO

Will update the contents as part of the tickets: "Test the whole IaC setup process#124" and "Document the K8s prerequisities needed by femdi-gateway-iac#123".

## Dependencies
The `EWC` module requires `Bash`, [jq](https://github.com/jqlang/jq) and [kubectl](https://kubernetes.io/docs/reference/kubectl/)

#TODO: Add template for .tfvars and explain variables

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
If some of the pods are not ready. Check the pods status using `kubectl`.
You might need to run pod unsealing manually using `kubectl -n vault exec -it pods/vault-<n> -- vault operator unseal` and provide keys stored in `vault_unseal_keys`.
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
> Make sure to store `vault_root_token` and `vault_unseal_keys` are stored somewhere safe. 
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
> This time make sure to store `dev-portal_keycloak_secret` somewhere safe. This the secret which dev-portal uses to authenticate to Keycloak and its generated dynamically.:
```bash
terraform output dev-portal_keycloak_secret
```
## APISIX Auto Scaling

TODO: the triggers for current auto scaling [there is a related ticket](https://app.zenhub.com/workspaces/rodeo-wp2---femdi-641aeac88a26d61ff17fc730/issues/gh/eumetnet/femdi-test/141).

APISIX uses the [limit-req](https://apisix.apache.org/docs/apisix/3.11/plugins/limit-req/) and [limit-count](https://apisix.apache.org/docs/apisix/3.11/plugins/limit-count/) plugins to limit user access. The internal counters for these plugins are not stored in any centralized place by default. When auto scaling occurs, each individual APISIX instance has its own counters, which allow users to exceed the intended rate limits. Also, DNS-level routing makes it possible (in theory at least) for users to have twice the limits available.

> [!IMPORTANT] 
> The currently supported solution by APISIX for sharing counters between APISIX instances and across different K8s clusters is to use Redis (cluster). The decision not to implement a Redis cluster at this point was made by the FEMDI expert team.

## Vault Token Renewals

APISIX and the Dev Portal use service tokens to communicate with Vault. These tokens have a maximum TTL of 768 hours (32 days). To prevent token revocation, a cron job is scheduled to run on the 1st and 15th of each month to reset the token period.

## Monitoring

### Alert Manager

The current default configuration sends all alerts gathered by the Prometheus Operator via email. To make the Alertmanager work, a working SMTP server is required. The SMTP server configuration is based on Gmail's SMTP settings, but different SMTP servers might require additional TLS configurations.

By default, the configuration does not group alerts; they are fired as they are received. If you want to group alerts, change the repeat interval etc. or add additional notification methods (e.g., Slack), you can modify the configuration accordingly or create a separate configuration for that.

To make the default Alertmanager configuration work, you need to provide the following variables:
- `alert_smtp_auth_username`: The SMTP username.
- `alert_smtp_auth_password`: The SMTP password.
- `alert_smtp_host`: The SMTP server host.
- `alert_email_sender`: The email address used to send alerts.
- `alert_email_recipients`: A list of email addresses to receive alerts.

If you want to skip the Alertmanager configuration for now, you can provide an empty string for the `alert_smtp_auth_username` and/or `alert_smtp_auth_password` variables.

For more advanced configurations, such as adding Slack notifications or grouping alerts, you can update the `receivers` and `route` sections in the `alertmanager_configs.tf` file or create a new configuration for a dedicated Alertmanager setup.


## Disaster Recovery

The disaster recovery plan includes backing up application databases and logical data, and restoring them from snapshot files. The backup and restore processes are performed using database-specific tools like `pg_dump` and `pg_restore`.

### Backups

Each application's database (Keycloak PostgreSQL, APISIX etcd, Vault raft) has a dedicated Cron job for backups. The backup schedule can be adjusted using Terraform if needed. Currently, backups are saved to an AWS S3 bucket. If there is no need to store files older than a certain number of days, bucket retention policies can be used to manage this.

### Restore

Each application has dedicated job(s) to restore data from snapshots. These jobs are invoked with independent commands, but the job templates are managed within Terraform.

> [!IMPORTANT]
> Ensure that the Terraform state and the actual cluster state are aligned before running restore jobs to avoid potential issues.
>
> You can try to take manual snapshot from desired database(s) before attempting the restore operation(s).

#### Keycloak Restore

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file

###########################################
# Optional manual backup before the restore
###########################################

JOB_NAME=$(kubectl create job --from=cronjob/keycloak-backup keycloak-backup-$(date +%s) -n keycloak -o jsonpath='{.metadata.name}')
POD_NAME=$(kubectl get pods -n keycloak -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}')
# Optionally, tail the logs
kubectl logs -f $POD_NAME -n keycloak
# Optionally, delete the job and its resources after completion
kubectl delete job $JOB_NAME -n keycloak

###########################################
# Restore
###########################################

export SNAPSHOT_NAME="specific_snapshot.db.gz" # Optionally provide a specific snapshot name if you need to restore a snapshot other than the latest one

# Create the restore job and capture the job name
JOB_NAME=$(kubectl get configmap keycloak-restore-backup -n keycloak -o jsonpath='{.data.job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs
kubectl logs -f $JOB_NAME -n keycloak

# Optionally, delete the job and its resources after completion
kubectl delete $JOB_NAME -n keycloak
```

#### Vault Restore

**Note:** Vault restore requires the UNSEAL_KEYS that were in use when the backup snapshot was taken. The VAULT_TOKEN is the latest root token that was created and used. If the Vault cluster becomes unresponsive or is completely wiped out, the existing cluster might need to be removed and a new one initialized. The new cluster will have new tokens and unseal keys. To access the cluster, the new token is needed, but unsealing the cluster requires the unseal keys used by the data in the snapshot.

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file

###########################################
# Optional manual backup before the restore
###########################################

JOB_NAME=$(kubectl create job --from=cronjob/vault-backup vault-backup-$(date +%s) -n vault -o jsonpath='{.metadata.name}')
POD_NAME=$(kubectl get pods -n vault -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}')
# Optionally, tail the logs
kubectl logs -f $POD_NAME -n vault
# Optionally, delete the job and its resources after completion
kubectl delete job $JOB_NAME -n vault

###########################################
# Restore
###########################################

export SNAPSHOT_NAME="specific_snapshot.snap.gz" # Optionally provide a specific snapshot name if need to restore other than latest snapshot file

JOB_TEMPLATE=$(kubectl get configmap vault-restore-backup -n vault -o jsonpath='{.data.job-template\.yaml}')

# Pass the unseal keys and vault token, place and logic to fetch these might need adjusting
# Create the restore job and capture the job name
JOB_NAME=$(
    UNSEAL_KEYS=$(jq -r '. | join(",")' ~/path-to/unseal_keys.txt) \
    VAULT_TOKEN=$(cat ~/path-to/vault_token.txt) \
    envsubst <<< "$JOB_TEMPLATE" | \
    kubectl create -f - -o name
)
# Optionally, tail the logs
kubectl logs -f $JOB_NAME -n vault
# Optionally, delete the job and its resources after completion
kubectl delete $JOB_NAME -n vault
```

#### APISIX Restore

```sh
export KUBECONFIG="~/.kube/config" # Replace with the path to your kubeconfig file

###########################################
# Optional manual backup before the restore
###########################################

JOB_NAME=$(kubectl create job --from=cronjob/apisix-backup apisix-backup-$(date +%s) -n apisix -o jsonpath='{.metadata.name}')
POD_NAME=$(kubectl get pods -n apisix -l job-name=$JOB_NAME -o jsonpath='{.items[0].metadata.name}')
# Optionally, tail the logs
kubectl logs -f $POD_NAME -n apisix
# Optionally, delete the job and its resources after completion
kubectl delete job $JOB_NAME -n apisix

###########################################
# Restore
###########################################

export SNAPSHOT_NAME="specific_snapshot.snap.gz" # Optionally provide a specific snapshot name if you need to restore a snapshot other than the latest one

# Create the pre-restore job and capture the job name
PRE_JOB_NAME=$(kubectl get configmap apisix-restore-backup -n apisix -o jsonpath='{.data.pre-job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs of the pre-restore job
kubectl logs -f $PRE_JOB_NAME -n apisix

# Optionally, delete the pre-restore job and its resources after completion
kubectl delete $PRE_JOB_NAME -n apisix

# Create the main restore job and capture the job name
MAIN_JOB_NAME=$(kubectl get configmap apisix-restore-backup -n apisix -o jsonpath='{.data.job-template\.yaml}' | envsubst | kubectl create -f - -o name)

# Optionally, tail the logs
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
