################################################################################

# Backups

################################################################################

# TODO consider using a service account for assuming AWS role - no need to use access key and secret key
# E.g. using service account with self-hosted k8s cluster requires own OIDC provider, keycloak, s3, dex etc.

################################################################################

# APISIX backup
################################################################################
locals {
  etcd_host = "http://apisix-etcd.apisix.svc.cluster.local:2379"
}
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
              image             = "ghcr.io/eurodeo/femdi-gateway-iac/cron-jobs:latest"
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
