################################################################################

# Keycloak
################################################################################

# Backup Cron Job
resource "kubernetes_secret" "keycloak_jobs_secrets" {
  metadata {
    name      = "keycloak-jobs"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.s3_bucket_access_key
    AWS_SECRET_ACCESS_KEY = var.s3_bucket_secret_key
  }

  type = "Opaque"

}

resource "kubernetes_cron_job_v1" "keycloak_backup" {
  metadata {
    name      = "keycloak-backup"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }

  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 3 # Keep the latest 3 failed jobs
    schedule                      = "0 3 * * *"
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
              name              = "keycloak-backup"
              image             = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/sh", "-c", "/usr/local/bin/keycloak-snapshot.sh"]

              env {
                name  = "POSTGRES_HOST"
                value = local.postgres_host
              }

              env {
                name  = "POSTGRES_DB"
                value = local.postgres_db_name
              }

              env {
                name  = "POSTGRES_USER"
                value = local.postgres_db_user
              }

              # A bit magic here to get the password from Keycloak Helm chart generated secret
              # Reference dev-portal-init/main.tf resource "helm_release" "keycloak" for more info
              env {
                name = "POSTGRES_PASSWORD"
                value_from {
                  secret_key_ref {
                    name = "${local.keycloak_helm_release_name}-postgresql"
                    key  = "password"
                  }
                }
              }

              env {
                name  = "S3_BUCKET_BASE_PATH"
                value = "${var.backup_bucket_base_path}/${kubernetes_namespace.keycloak.metadata.0.name}/"
              }

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.keycloak_jobs_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.keycloak_jobs_secrets.metadata.0.name
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

resource "kubernetes_service_account" "keycloak_restore_sa" {
  metadata {
    name      = "keycloak-restore-sa"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
}

resource "kubernetes_role" "keycloak_restore_role" {
  metadata {
    name      = "keycloak-restore-role"
    namespace = kubernetes_namespace.keycloak.metadata[0].name
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets"]
    verbs      = ["get"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["statefulsets/scale"]
    verbs      = ["get", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "keycloak_restore_role_binding" {
  metadata {
    name      = "keycloak-restore-role-binding"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.keycloak_restore_sa.metadata.0.name
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.keycloak_restore_role.metadata.0.name
    api_group = "rbac.authorization.k8s.io"
  }
}

# Restore from backup
locals {
  keycloak_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "keycloak-restore-backup-"
      namespace    = "${kubernetes_namespace.keycloak.metadata.0.name}"
      labels = {
        "app.kubernetes.io/instance" = "keycloak-restore-backup"
      }
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          serviceAccountName = "${kubernetes_service_account.keycloak_restore_sa.metadata.0.name}"
          restartPolicy      = "Never"
          containers = [
            {
              name            = "keycloak-restore-backup"
              image           = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              imagePullPolicy = "Always"
              command         = ["/bin/sh", "-c", "/usr/local/bin/keycloak-restore.sh"]
              env = [
                {
                  name  = "SNAPSHOT_NAME"
                  value = "$${SNAPSHOT_NAME}" # Make it possible to override the default value at runtime with envsubst
                },
                {
                  name  = "S3_BUCKET_BASE_PATH"
                  value = "${var.backup_bucket_base_path}/${kubernetes_namespace.keycloak.metadata.0.name}/"
                },
                {
                  name = "AWS_ACCESS_KEY_ID"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.keycloak_jobs_secrets.metadata.0.name}"
                      key  = "AWS_ACCESS_KEY_ID"
                    }
                  }
                },
                {
                  name = "AWS_SECRET_ACCESS_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.keycloak_jobs_secrets.metadata.0.name}"
                      key  = "AWS_SECRET_ACCESS_KEY"
                    }
                  }
                },
                {
                  name  = "NAMESPACE"
                  value = "${kubernetes_namespace.keycloak.metadata.0.name}"
                },
                {
                  name  = "POSTGRES_HOST"
                  value = "${local.postgres_host}"
                },
                {
                  name  = "POSTGRES_DB"
                  value = "${local.postgres_db_name}"
                },
                {
                  name  = "POSTGRES_USER"
                  value = "${local.postgres_db_user}"
                },
                {
                  name = "POSTGRES_PASSWORD"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${local.keycloak_helm_release_name}-postgresql"
                      key  = "password"
                    }
                  }
                },
                {
                  name  = "REPLICA_COUNT"
                  value = format("%s", var.keycloak_replicas)
                },
                {
                  name  = "KEYCLOAK_HELM_RELEASE_NAME"
                  value = "${local.keycloak_helm_release_name}"
                },
              ]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_config_map" "keycloak_restore_backup_template" {
  metadata {
    name      = "keycloak-restore-backup"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }

  data = {
    "job-template.yaml" = yamlencode(local.keycloak_restore_job_template)
  }

}
