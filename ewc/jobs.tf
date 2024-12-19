# TODO consider using a service account for assuming AWS role - no need to use access key and secret key
# E.g. using service account with self-hosted k8s cluster requires own OIDC provider, keycloak, s3, dex etc.

################################################################################

# Vault
################################################################################

# Vault backup
resource "kubernetes_service_account" "vault_backup_cron_job_service_account" {
  metadata {
    name      = "vault-backup-cron-job-sa"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  automount_service_account_token = true # This is the default value

  depends_on = [module.ewc-vault-init]

}

resource "kubernetes_secret" "vault_backup_cron_job_secrets" {
  metadata {
    name      = "vault-backup-cron-jobs"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.s3_bucket_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_bucket_secret_key
  }

  type = "Opaque"
}

resource "kubernetes_cron_job_v1" "vault_backup" {
  metadata {
    name      = "vault-backup"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 3 # Keep the latest 3 failed jobs
    schedule                      = "1 0 * * *"
    timezone                      = "Etc/UTC"
    starting_deadline_seconds     = 43200 # 12 hours
    successful_jobs_history_limit = 1     # Keep the latest

    job_template {
      metadata {}
      spec {
        backoff_limit = 6 # This is the default value
        template {
          metadata {}
          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account.vault_backup_cron_job_service_account.metadata.0.name
            container {
              name              = "vault-backup"
              image             = "ghcr.io/eurodeo/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/sh", "-c", "/usr/local/bin/vault-snapshot.sh"]

              env {
                name  = "VAULT_ADDR"
                value = local.vault_host
              }

              env {
                name  = "S3_BUCKET_BASE_PATH"
                value = var.vault_backup_bucket_base_path
              }

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.vault_backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.vault_backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_SECRET_ACCESS_KEY"
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [module.ewc-vault-init]

}

# Vault restore
locals {
  vault_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "vault-restore-backup-"
      namespace    = module.ewc-vault-init.vault_namespace_name
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          restartPolicy = "Never"
          containers = [
            {
              name    = "vault-restore-backup"
              image   = "ghcr.io/eurodeo/femdi-gateway-iac/jobs:latest"
              command = ["/bin/sh", "-c", "/usr/local/bin/vault-restore.sh"]
              env = [
                {
                  name  = "SNAPSHOT_NAME"
                  value = "latest"
                },
                {
                  name  = "S3_BUCKET_BASE_PATH"
                  value = var.vault_backup_bucket_base_path
                },
                {
                  name = "AWS_ACCESS_KEY_ID"
                  valueFrom = {
                    secretKeyRef = {
                      name = kubernetes_secret.vault_backup_cron_job_secrets.metadata[0].name
                      key  = "AWS_ACCESS_KEY_ID"
                    }
                  }
                },
                {
                  name = "AWS_SECRET_ACCESS_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = kubernetes_secret.vault_backup_cron_job_secrets.metadata[0].name
                      key  = "AWS_SECRET_ACCESS_KEY"
                    }
                  }
                },
                {
                  name  = "NAMESPACE"
                  value = module.ewc-vault-init.vault_namespace_name
                },
                {
                  name  = "KEY_THRESHOLD"
                  value = var.vault_key_treshold
                },
                {
                  name  = "UNSEAL_KEYS"
                  value = ""
                }
              ]
            }
          ]
        }
      }
    }
  }

  depends_on = [module.ewc-vault-init]

}

resource "kubernetes_config_map" "vault_restore_backup" {
  metadata {
    name      = "vault-restore-backup"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  data = {
    "job-template.yaml" = yamlencode(local.vault_restore_job_template)
  }

  depends_on = [module.ewc-vault-init]

}


################################################################################

# APISIX backup
################################################################################
resource "kubernetes_secret" "apisix_backup_cron_job_secrets" {
  metadata {
    name      = "apisix-backup-cron-jobs"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.s3_bucket_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_bucket_secret_key
  }

  type = "Opaque"
}

resource "kubernetes_cron_job_v1" "apisix_backup" {
  metadata {
    name      = "apisix-backup"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 3 # Keep the latest 3 failed jobs
    schedule                      = "1 0 * * *"
    timezone                      = "Etc/UTC"
    starting_deadline_seconds     = 43200 # 12 hours
    successful_jobs_history_limit = 1     # Keep the latest

    job_template {
      metadata {}
      spec {
        backoff_limit = 6 # This the default value
        template {
          metadata {}
          spec {
            restart_policy = "OnFailure"
            container {
              name              = "apisix-backup"
              image             = "ghcr.io/eurodeo/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/sh", "-c", "/usr/local/bin/apisix-snapshot.sh"]

              env {
                name  = "ETCD_ENDPOINT"
                value = local.etcd_host
              }

              env {
                name  = "S3_BUCKET_BASE_PATH"
                value = var.apisix_backup_bucket_base_path
              }

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.apisix_backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.apisix_backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_SECRET_ACCESS_KEY"
                  }
                }
              }
            }
          }
        }
      }
    }
  }

}
