# EWC

## Dependencies

The `EWC` module requires `Bash`, [jq](https://github.com/jqlang/jq), [kubectl](https://kubernetes.io/docs/reference/kubectl/) and [AWS CLI](https://aws.amazon.com/cli/)

## Prerequisites

### Rancher Manager and RKE2 cluster deployment

There should be Rancher Manager and RKE2 Kubernetes cluster deployment running. Instructions how to deploy one in ECMWF side https://confluence.ecmwf.int/display/EWCLOUDKB/EWC+Kubernetes+Self-service.

TODO need to find out corresponding instructions from EUMETSAT side since at least the available options for Rancher Manager provisioning differs.

In EUMETSAT side these differs so far: security group is ssh-http-https, networks is internal and floating IP is external. This will be updated if more is find out.

### AWS Account

One should have access to correct AWS account. TODO how FMI people gain access to given AWS account?

Once access to given account is granted then you need to configure AWS CLI and [SSO](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html). To configure AWS SSO you can run `aws configure sso` or do it manually by adding a correct profile to ~/.aws/config.
Profile template:
```bash
[profile fmi_meteogate]
sso_start_url =
sso_region = eu-north-1
sso_account_id =
sso_role_name = 
region = eu-north-1
output = json
```

## Bootstrap variables

Copy and rename `tfvars_template` to something like `<cluster_name>.tfvars` and copy and rename `env_params_template` to `.env.params` or something else if that describes better.

Fill both files with appropriate variables. It is also possible to provide the .tfvars variables inline when running terraform. You can find more about those parameters from corresponding templates.

Variables `keycloak/github_idp_client_secret` and `keycloak/google_idp_client_secret` requires running OAuth apps.

### Setup Github OAuth App

1. Navigate to your Github account Settings -> Developer Settings -> OAuth Apps and click "New OAauth App" or from URL https://github.com/settings/applications/new. 

2. Fill in the required fields:

    * Application Name = Give a name for your app

    * Homepage URL = https://<dev_portal/subdomain>.meteogate.eu

    * Authorization callback URL = https://<keycloak/subdomain>.meteogate.eu/realms/meteogate/broker/github/endpoint

3. Click register application.

4. In next page you can fetch the client ID and generate client secret. Use these as values for `keycloak/github_idp_client_id` and `keycloak/github_idp_client_secret`.
 
### Setup Google Auth App

1. Navigate to Google Cloud console 

2. Choose existing project or create a new project for OAuth client

3. Navigate to APIs & Services > OAuth consent screen then choose Clients and click "+ Create client":

    * Application type = Web application

    * Name = Give it a name

    * Add new Authorized JavaScript origin(s)
      * URI = https://<dev_portal/subdomain>.meteogate.eu

    * Add Authorized redirect URI(s)
      * URI = https://<keycloak/subdomain>.meteogate.eu/realms/meteogate/broker/google/endpoint

4. Click Create and then copy the generated Client ID and Client secret. Use these as values for `keycloak/google_idp_client_id` and `keycloak/google_idp_client_secret`.


Once you have filled both of the files bootstrap the .env.parameters to AWS SSM Parameter Store by running:
```bash
AWS_PROFILE=fmi_meteogate ./bootstrap_params.sh .env.params
```

## Init

Initialize the Terraform project:
```bash
terraform init
```

Check existing workspaces
```bash
terraform workspace list
```

Create new workspace for the cluster
```bash
terraform workspace new <cluster_name>
```

> [!IMPORTANT] 
> The EWC part of Terraform code has to be run in two separate part for bootstrapping the Vault instances


## First

Run the ewc-vault-init module:
```bash
terraform apply -target module.ewc-vault-init -var-file=<cluster_name>.tfvars
```
Provide the needed terraform variables if no `-var-file` file is used.

The expected output should look something like this.
All the vault pods should be ready after the initialization.
If some of the pods are not ready. Check the pods status using `kubectl`.
You might need to run pod unsealing manually using `kubectl -n vault exec -it pods/vault-<n> -- vault operator unseal` and provide keys stored in `vault_unseal_keys`.
```txt
Outputs:

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
> Make sure to store `vault_root_token` as `/<cluster_name>/vault/root_token` and `vault_unseal_keys` as `/<cluster_name>/vault/unseal_keys` to AWS Parameter Store. You can save these manually to AWS or save the values to .env.params file and run again `AWS_PROFILE=fmi_meteogate ./bootstrap_params.sh`
>
> Make sure you copy the `vault_root_token` and `vault_unseal_keys` before you run any other Terraform commands. These will be available only once!
>
> If the Vault is recreated for a data restore operation, do not delete the previous `vault_unseal_keys`. Continue using the old unseal keys and ignore the new ones. The new `vault_root_token` is needed and need to be updated to AWS Parameter Store. For more details, see the [Vault Restore](#vault-restore) section.

You can access sensitive values using commands:
```bash
terraform output vault_root_token
terraform output vault_unseal_keys
```

## Second

Bootstrap Vault root token and unseal keys to parameter store

```bash
AWS_PROFILE=fmi_meteogate ./bootstrap_params.sh .env.params
```

Run the rest of the Terraform code:
```bash
terraform apply -var-file=<cluster_name>.tfvars
```
Expected output looks like this.
```txt
Outputs:

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

## Manual Steps after Second run

1. To enable Keycloak PostgreSQL backups you need to change `backups_enabled = true` in [ewc/dev-portal-init/main.tf](dev-portal-init/main.tf#L87) file and then run `terraform apply -var-file=<cluster_name>.tfvars`.

2. Register this platform to [API management tool](https://github.com/EUMETNET/api-management-tool-poc) repository (There are instructions in that repo too):
    * Append used `cluster_name` variable value in UPPERCASE to the repository variable **PLATFORMS** list
    * Add `cluster_name` variable value in UPPERCASE to [health route's](https://github.com/EUMETNET/api-management-tool-poc/blob/main/configs/routes/health.yaml#L3) platforms list.
    * (Add additional routes to this platform either by creating new one or adding existing route to this platform by adding cluster_name variable in UPPERCASE to the route yaml platforms list)
      * if route requires upstream API key then add that to the Vault of this platform
    * Management tool should run action "Test and deploy new APISIX configurations" once the configuration changes are merged/pushed to main branch

3. In case there will be another cluster that is going to be attached to this cluster's Dev Portal then run previous steps to that one and after that cluster is set up then: 
    * add that cluster's name to AWS Parameter store in variable `/<this-cluster-name>/dev_portal/external_cluster_names`.
    * run `terraform apply -var-file=<cluster_name>.tfvars` again and then `kubectl rollout restart deployment dev-portal-backend -n dev-portal` to make dev portal backend pick up the new env including the another cluster information.


## In case Terraform state drifts from actual resources

The following might help to solve out the drift issue. A safer alternative for this delete operation is to use `terraform import <resource> <id>`.

1. Delete the drifted terraform.tfstate versions from s3 bucket. Backup or copy the versions you are about to delete somewhere safe to be able to restore if needed. Your workspace's terraform.tfstate file is located at s3://meteogate-iac-terraform-states/env:/<workspace_name>/clusters/terraform.tfstate
2. Delete the /.terraform directory from your local machine.
3. Reinitialize the backend by running `terraform init -reconfigure`
4. Check the workspaces `terraform workspace list` and use your workspace `terraform workspace select <workspace_name>`
5. Run terraform plan to see if that solved the problem `terraform plan -var-file=<cluster_name>.tfvars`


## Parameters

Parameters stored in AWS SSM Parameter Store are interacted with in files ssm.tf and the actual values to terraform files are provided through locals.tf to make it single point of truth. Also other locals should be preferrably stored to locals.tf files.

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

The default Alertmanager configuration are stored AWS param store as:
- `/alert_manager/smtp_auth_username`: The SMTP username.
- `/alert_manager/smtp_auth_password`: The SMTP password.
- `/alert_manager/smtp_host`: The SMTP server host.
- `/alert_manager/email_sender`: The email address used to send alerts.
- `/alert_manager/email_recipients`: A list of email addresses to receive alerts.

If you want to skip the Alertmanager configuration for now, you can change the `/alert_manager/smtp_auth_username` and/or `alert_manager/smtp_auth_password` variables values to "false" in parameter store.

For more advanced configurations, such as adding Slack notifications or grouping alerts, you can update the `receivers` and `route` sections in the `alertmanager_configs.tf` file or create a new configuration for a dedicated Alertmanager setup.

## Disaster Recovery

### Keycloak

#### Backups

The Cloudnative-pg chart includes backups. More info about the backups: https://cloudnative-pg.io/documentation/1.20/backup/.

#### Restore

Joonas has dedicated instructions for recovery process.

### Vault and APISIX

The disaster recovery plan includes backing up application databases and logical data, and restoring them from snapshot files.

Both backup and restore jobs uses custom Dockerfile to perform tasks. The Dockerfile and job scripts are located in `/jobs/` directory. There is Github Action in `.github/workflows/upload_jobs_image.yml` that uploads new image to Github Container Registry in case Dockerfile or scripts needs modfications.

#### Backups

Both application's database (APISIX etcd, Vault raft) has a dedicated Cron job for backups. The backup schedule can be adjusted using Terraform if needed. Currently, backups are saved to an AWS S3 bucket. If there is no need to store files older than a certain number of days, bucket retention policies can be used to manage this.

#### Restore

Both applications has dedicated job(s) to restore data from snapshots. These jobs are invoked with independent commands, but the job templates are managed within Terraform.

> [!IMPORTANT]
> Ensure that the Terraform state and the actual cluster state are aligned before running restore jobs to avoid potential issues.
>
> You can try to take manual snapshot from desired database(s) before attempting the restore operation(s).

##### Vault Restore

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
    UNSEAL_KEYS=$(AWS_PROFILE=fmi_meteogate aws ssm get-parameter --name "/cluster_name/vault/unseal_keys" --with-decryption --query "Parameter.Value" --region eu-north-1 --output text || { echo "Failed to fetch unseal keys"; exit 1; }) \
    VAULT_TOKEN=$(AWS_PROFILE=fmi_meteogate aws ssm get-parameter --name "/cluster_name/vault/root_token" --with-decryption --query "Parameter.Value" --region eu-north-1 --output text || { echo "Failed to fetch root token"; exit 1; })\
    envsubst <<< "$JOB_TEMPLATE" | \
    kubectl create -f - -o name
)
# Optionally, tail the logs
kubectl logs -f $JOB_NAME -n vault
# Optionally, delete the job and its resources after completion
kubectl delete $JOB_NAME -n vault
```

##### APISIX Restore

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
