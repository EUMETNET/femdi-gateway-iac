################################################################################
# Backups
################################################################################

# TODO consider using a service account for assuming AWS role - no need to use access key and secret key
# E.g. using service account with self-hosted k8s cluster requires own OIDC provider, keycloak, s3, dex etc.


################################################################################
# Common
################################################################################

resource "kubernetes_namespace" "backup_cron_jobs" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = rancher2_project.gateway.id
    }

    name = "backup-cron-jobs"
  }
}

resource "kubernetes_secret" "backup_cron_job_secrets" {
  metadata {
    name      = "backup-cron-jobs"
    namespace = kubernetes_namespace.backup_cron_jobs.metadata.0.name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.s3_bucket_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_bucket_secret_key
  }

  type = "Opaque"
}

# Role that allows read access to the secret defined above
resource "kubernetes_role" "secret_access_role" {
  metadata {
    name      = "secret-access-role"
    namespace = kubernetes_namespace.backup_cron_jobs.metadata[0].name
  }

  rule {
    api_groups     = [""] # secrets are part of core API group
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.backup_cron_job_secrets.metadata.0.name]
    verbs          = ["get"]
  }
}


################################################################################
# Vault
################################################################################
resource "kubernetes_service_account" "vault_backup_cron_job_service_account" {
  metadata {
    name      = "vault-backup-cron-job-sa"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  depends_on = [module.ewc-vault-init]

}

# Role binding that allows the service account to access the common secret in different namespace
resource "kubernetes_role_binding" "vault_backup_secret_access_binding" {
  metadata {
    name      = "vault-backup-secret-access-binding"
    namespace = kubernetes_namespace.backup_cron_jobs.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_backup_cron_job_service_account.metadata[0].name
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.secret_access_role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
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
        backoff_limit = 6 # This the default value
        template {
          metadata {}
          spec {
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account.vault_backup_cron_job_service_account.metadata.0.name
            container {
              name              = "vault-backup"
              image             = "ghcr.io/eurodeo/femdi-gateway-iac/vault-snapshot:latest"
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
                    name = kubernetes_secret.backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.backup_cron_job_secrets.metadata.0.name
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


################################################################################
# APISIX backup
################################################################################
resource "kubernetes_service_account" "apisix_backup_cron_job_service_account" {
  metadata {
    name      = "apisix-backup-cron-job-sa"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

}

resource "kubernetes_role_binding" "apisix_backup_secret_access_binding" {
  metadata {
    name      = "apisix-backup-secret-access-binding"
    namespace = kubernetes_namespace.backup_cron_jobs.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.apisix_backup_cron_job_service_account.metadata[0].name
    namespace = kubernetes_namespace.apisix.metadata[0].name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.secret_access_role.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
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
            restart_policy       = "OnFailure"
            service_account_name = kubernetes_service_account.apisix_backup_cron_job_service_account.metadata.0.name
            container {
              name              = "apisix-backup"
              image             = "ghcr.io/eurodeo/femdi-gateway-iac/vault-snapshot:latest"
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
                    name = kubernetes_secret.backup_cron_job_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.backup_cron_job_secrets.metadata.0.name
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
