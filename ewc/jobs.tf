# TODO consider using a service account for assuming AWS role - no need to use access key and secret key
# E.g. using service account with self-hosted k8s cluster requires own OIDC provider, keycloak, s3, dex etc.

################################################################################

# Vault
################################################################################

# Service token renewal
resource "kubernetes_cron_job_v1" "vault_token_renewal" {
  metadata {
    name      = "vault-token-renewal"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  spec {
    concurrency_policy            = "Replace"
    failed_jobs_history_limit     = 3              # Keep the latest 3 failed jobs
    schedule                      = "0 4 1,15 * *" # Run at 4 AM twice a month to provide sufficient buffer
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
            service_account_name = kubernetes_service_account.vault_jobs_service_account.metadata.0.name
            container {
              name              = "vault-token-renewal"
              image             = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/bash", "-c", "/usr/local/bin/vault-token-renewal.sh"]

              env {
                name  = "VAULT_ADDR"
                value = local.vault_host
              }

              env {
                name  = "VAULT_ROLE"
                value = vault_kubernetes_auth_backend_role.cron-job.role_name
              }


              volume_mount {
                name       = "tokens-volume"
                mount_path = "/tmp/secret/tokens"
                sub_path   = "tokens"
              }



            }

            volume {
              name = "tokens-volume"
              secret {
                secret_name = kubernetes_secret.vault_jobs_secrets.metadata.0.name
                items {

                  key  = "TOKENS_TO_RENEW"
                  path = "tokens"
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

# Backup
resource "kubernetes_service_account" "vault_jobs_service_account" {
  metadata {
    name      = "vault-jobs-sa"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  automount_service_account_token = true # This is the default value

  depends_on = [module.ewc-vault-init]

}

resource "kubernetes_role" "vault_restore_role" {
  metadata {
    name      = "vault-restore-role"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }

  rule {
    api_groups = [""]
    resources  = ["pods/exec"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding" "vault_restore_role_binding" {
  metadata {
    name      = "vault-restore-role-binding"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.vault_jobs_service_account.metadata.0.name
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.vault_restore_role.metadata.0.name
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "kubernetes_secret" "vault_jobs_secrets" {
  metadata {
    name      = "vault-jobs"
    namespace = module.ewc-vault-init.vault_namespace_name
  }

  data = {
    AWS_ACCESS_KEY_ID     = data.terraform_remote_state.global.outputs.backup_aws_access_key_id
    AWS_SECRET_ACCESS_KEY = data.terraform_remote_state.global.outputs.backup_aws_secret_access_key
    TOKENS_TO_RENEW       = "${join("\n", [vault_token.apisix-global.client_token, vault_token.dev-portal-global.client_token, vault_token.prometheus.client_token])}"
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
    schedule                      = "0 3 * * *"
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
            service_account_name = kubernetes_service_account.vault_jobs_service_account.metadata.0.name
            container {
              name              = "vault-backup"
              image             = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/sh", "-c", "/usr/local/bin/vault-snapshot.sh"]

              env {
                name  = "VAULT_ADDR"
                value = local.vault_host
              }

              env {
                name  = "S3_BUCKET_BASE_PATH"
                value = "${data.terraform_remote_state.global.outputs.backup_bucket_name}/${var.cluster_name}/${module.ewc-vault-init.vault_namespace_name}/"
              }

              env {
                name  = "VAULT_ROLE"
                value = vault_kubernetes_auth_backend_role.cron-job.role_name
              }

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.vault_jobs_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.vault_jobs_secrets.metadata.0.name
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

# Restore
locals {
  vault_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "vault-restore-backup-"
      namespace    = "${module.ewc-vault-init.vault_namespace_name}"
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          serviceAccountName = "${kubernetes_service_account.vault_jobs_service_account.metadata.0.name}"
          restartPolicy      = "Never"
          containers = [
            {
              name            = "vault-restore-backup"
              image           = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              imagePullPolicy = "Always"
              command         = ["/bin/sh", "-c", "/usr/local/bin/vault-restore.sh"]
              env = [
                {
                  name  = "SNAPSHOT_NAME"
                  value = "$${SNAPSHOT_NAME}"
                },
                {
                  name  = "S3_BUCKET_BASE_PATH"
                  value = "${data.terraform_remote_state.global.outputs.backup_bucket_name}/${var.cluster_name}/${module.ewc-vault-init.vault_namespace_name}/"
                },
                {
                  name = "AWS_ACCESS_KEY_ID"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.vault_jobs_secrets.metadata.0.name}"
                      key  = "AWS_ACCESS_KEY_ID"
                    }
                  }
                },
                {
                  name = "AWS_SECRET_ACCESS_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.vault_jobs_secrets.metadata.0.name}"
                      key  = "AWS_SECRET_ACCESS_KEY"
                    }
                  }
                },
                {
                  name  = "NAMESPACE"
                  value = "${module.ewc-vault-init.vault_namespace_name}"
                },
                {
                  name  = "VAULT_TOKEN"
                  value = "$${VAULT_TOKEN}"
                },
                {
                  name  = "KEY_THRESHOLD"
                  value = format("%s", var.vault_key_treshold)
                },
                {
                  name  = "UNSEAL_KEYS"
                  value = "$${UNSEAL_KEYS}"
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

# APISIX
################################################################################

# Backup
resource "kubernetes_secret" "apisix_jobs_secrets" {
  metadata {
    name      = "apisix-jobs"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  data = {
    AWS_ACCESS_KEY_ID     = data.terraform_remote_state.global.outputs.backup_aws_access_key_id
    AWS_SECRET_ACCESS_KEY = data.terraform_remote_state.global.outputs.backup_aws_secret_access_key
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
              name              = "apisix-backup"
              image             = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              image_pull_policy = "Always" # TODO change to IfNotPresent once tested out to be working
              command           = ["/bin/sh", "-c", "/usr/local/bin/apisix-snapshot.sh"]

              env {
                name  = "ETCD_ENDPOINT"
                value = local.apisix_etcd_host
              }

              env {
                name  = "S3_BUCKET_BASE_PATH"
                value = "${data.terraform_remote_state.global.outputs.backup_bucket_name}/${var.cluster_name}/${kubernetes_namespace.apisix.metadata.0.name}/"
              }

              env {
                name = "AWS_ACCESS_KEY_ID"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.apisix_jobs_secrets.metadata.0.name
                    key  = "AWS_ACCESS_KEY_ID"
                  }
                }
              }

              env {
                name = "AWS_SECRET_ACCESS_KEY"
                value_from {
                  secret_key_ref {
                    name = kubernetes_secret.apisix_jobs_secrets.metadata.0.name
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

# Restore
resource "kubernetes_service_account" "apisix_restore_sa" {
  metadata {
    name      = "apisix-restore-sa"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }
}

resource "kubernetes_role" "apisix_restore_role" {
  metadata {
    name      = "apisix-restore-role"
    namespace = kubernetes_namespace.apisix.metadata.0.name
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

resource "kubernetes_role_binding" "apisix_restore_role_binding" {
  metadata {
    name      = "apisix-restore-role-binding"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.apisix_restore_sa.metadata.0.name
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  role_ref {
    kind      = "Role"
    name      = kubernetes_role.apisix_restore_role.metadata.0.name
    api_group = "rbac.authorization.k8s.io"
  }
}

locals {
  apisix_pre_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "apisix-pre-restore-backup-"
      namespace    = "${kubernetes_namespace.apisix.metadata.0.name}"
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          serviceAccountName = "${kubernetes_service_account.apisix_restore_sa.metadata.0.name}"
          restartPolicy      = "Never"
          containers = [
            {
              name            = "pre-apisix-restore-backup"
              image           = "bitnami/kubectl:1.28"
              imagePullPolicy = "IfNotPresent"
              command = [
                "/bin/sh",
                "-c",
                <<-EOF
                set -e
                echo "Scaling down the etcd StatefulSet...";
                kubectl scale statefulset ${local.apisix_helm_release_name}-etcd --replicas=0 -n ${kubernetes_namespace.apisix.metadata.0.name};

                echo "Waiting for StatefulSet pods to terminate...";
                kubectl wait --for=delete pod -l app.kubernetes.io/instance=${local.apisix_helm_release_name},app.kubernetes.io/name=etcd -n ${kubernetes_namespace.apisix.metadata.0.name} --timeout=300s

                echo "StatefulSet is scaled down.";
                EOF
              ]
            }
          ]
        }
      }
    }
  }
  apisix_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "apisix-restore-backup-"
      namespace    = "${kubernetes_namespace.apisix.metadata.0.name}"
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          restartPolicy = "Never"
          containers = [
            {
              name            = "apisix-restore-backup"
              image           = "ghcr.io/eumetnet/femdi-gateway-iac/jobs:latest"
              imagePullPolicy = "Always"
              command         = ["/bin/sh", "-c", "/usr/local/bin/apisix-restore.sh"]
              env = [
                {
                  name  = "SNAPSHOT_NAME"
                  value = "$${SNAPSHOT_NAME}"
                },
                {
                  name  = "S3_BUCKET_BASE_PATH"
                  value = "${data.terraform_remote_state.global.outputs.backup_bucket_name}/${var.cluster_name}/${kubernetes_namespace.apisix.metadata.0.name}/"
                },
                {
                  name = "AWS_ACCESS_KEY_ID"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.apisix_jobs_secrets.metadata.0.name}"
                      key  = "AWS_ACCESS_KEY_ID"
                    }
                  }
                },
                {
                  name = "AWS_SECRET_ACCESS_KEY"
                  valueFrom = {
                    secretKeyRef = {
                      name = "${kubernetes_secret.apisix_jobs_secrets.metadata.0.name}"
                      key  = "AWS_SECRET_ACCESS_KEY"
                    }
                  }
                },
                {
                  name  = "NAMESPACE"
                  value = "${kubernetes_namespace.apisix.metadata.0.name}"
                },
                {
                  name  = "REPLICA_COUNT"
                  value = format("%s", var.apisix_etcd_replicas)
                },
                {
                  name  = "APISIX_HELM_RELEASE_NAME"
                  value = "${local.apisix_helm_release_name}"
                },
              ]
              volumeMounts = [
                for i in range(var.apisix_etcd_replicas) : {
                  name      = "data-${local.apisix_helm_release_name}-etcd-${i}"
                  mountPath = "/etcd-volumes/data-${local.apisix_helm_release_name}-etcd-${i}"
                }
              ]
            }
          ],
          volumes = [
            for i in range(var.apisix_etcd_replicas) : {
              name = "data-${local.apisix_helm_release_name}-etcd-${i}"
              persistentVolumeClaim = {
                claimName = "data-${local.apisix_helm_release_name}-etcd-${i}"
              }
            }
          ]
        }
      }
    }
  }
  apisix_post_restore_job_template = {
    apiVersion = "batch/v1"
    kind       = "Job"
    metadata = {
      generateName = "apisix-post-restore-backup-"
      namespace    = "${kubernetes_namespace.apisix.metadata.0.name}"
    }
    spec = {
      backoffLimit = 0
      template = {
        spec = {
          serviceAccountName = "${kubernetes_service_account.apisix_restore_sa.metadata.0.name}"
          restartPolicy      = "Never"
          containers = [
            {
              name            = "post-apisix-restore-backup"
              image           = "bitnami/kubectl:1.28"
              imagePullPolicy = "IfNotPresent"
              command = [
                "/bin/sh",
                "-c",
                <<-EOF
                set -e
                echo "Scaling up the etcd StatefulSet back to its original replica count..";
                kubectl scale statefulset ${local.apisix_helm_release_name}-etcd --replicas=${var.apisix_etcd_replicas} -n ${kubernetes_namespace.apisix.metadata.0.name};

                echo "Waiting for StatefulSet pods to scale up...";
                kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=${local.apisix_helm_release_name},app.kubernetes.io/name=etcd -n ${kubernetes_namespace.apisix.metadata.0.name} --timeout=300s

                echo "StatefulSet is scaled up.";
                EOF
              ]
            }
          ]
        }
      }
    }
  }

}

resource "kubernetes_config_map" "apisix_restore_backup" {
  metadata {
    name      = "apisix-restore-backup"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }

  data = {
    "pre-job-template.yaml"  = yamlencode(local.apisix_pre_restore_job_template)
    "job-template.yaml"      = yamlencode(local.apisix_restore_job_template)
    "post-job-template.yaml" = yamlencode(local.apisix_post_restore_job_template)
  }

}
