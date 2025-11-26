################################################################################
# Install Keycloak & PostgreSQL
################################################################################
resource "kubernetes_namespace" "keycloak" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = var.rancher_project_id
    }

    name = "keycloak"
  }
}

locals {
  postgres_host              = "${local.keycloak_helm_release_name}-postgresql.${kubernetes_namespace.keycloak.metadata.0.name}.svc.cluster.local"
  postgres_db_name           = "bitnami_keycloak" # Default from Helm chart
  postgres_db_user           = "keycloak"         # default from Helm chart
  keycloak_helm_release_name = "keycloak"
}

# --------------------------------------------------------
# PostgreSQL
# --------------------------------------------------------
resource "random_password" "keycloak_postgresql_password" {
  length  = 32
  special = true
}

resource "kubernetes_secret" "keycloak_postgresql" {
  metadata {
    name      = "keycloak-postgresql-new"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
  data = {
    username = "keycloak"
    password = random_password.keycloak_postgresql_password.result
  }
  type = "Opaque"
}

resource "kubernetes_secret" "keycloak_postgresql_jobs" {
  metadata {
    name      = "keycloak-postgresql-jobs"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
  data = {
    ACCESS_KEY_ID     = var.backup_bucket_access_key
    ACCESS_SECRET_KEY = var.backup_bucket_secret_key
  }
  type = "Opaque"
}

resource "helm_release" "cnpg_operator" {
  name       = "cnpg-operator"
  namespace  = kubernetes_namespace.keycloak.metadata.0.name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.26.1"

  set = [
    {
      name  = "config.clusterWide"
      value = "false"
    }
  ]

  depends_on = [
    kubernetes_namespace.keycloak
  ]
}

# First initial installation WITH backups.enabled = false
# Then backups.enabled = true in a separate apply
resource "helm_release" "cnpg_cluster" {
  name       = "cnpg"
  namespace  = kubernetes_namespace.keycloak.metadata.0.name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cluster"
  version    = "0.3.1"

  values = [
    templatefile("./templates/helm-values/postgres-values-template.yaml", {
      db_secret_name          = kubernetes_secret.keycloak_postgresql.metadata[0].name
      backup_destination_path = "s3://${var.backup_bucket_name}/${var.cluster_name}/${kubernetes_namespace.keycloak.metadata.0.name}"
      backup_secret_name      = kubernetes_secret.keycloak_postgresql_jobs.metadata[0].name
      postgresql_version      = "16.4"
      backups_enabled         = false # Change to true after initial installation
    })
  ]

  depends_on = [
    helm_release.cnpg_operator,
    kubernetes_secret.keycloak_postgresql,
    kubernetes_secret.keycloak_postgresql_jobs
  ]
}

# --------------------------------------------------------
# Keycloak
# --------------------------------------------------------

# Create configmap for realm json
resource "kubernetes_config_map" "realm-json" {
  metadata {
    name      = "realm-json"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
  data = {
    "realm.json" = templatefile("./keycloak-realm/realm-export.json", {
      dev_portal_api_secret    = jsonencode(local.dev_portal_keycloak_secret)
      google_idp_client_id     = local.google_idp_client_id
      google_idp_client_secret = local.google_idp_client_secret
      github_idp_client_id     = local.github_idp_client_id
      github_idp_client_secret = local.github_idp_client_secret
      redirect_uris = [
        "https://${var.dev_portal_subdomain}.${var.dns_zone}",
        "https://${var.geoweb_subdomain}.${var.dns_zone}/code"
      ]
      web_origins = [
        "https://${var.dev_portal_subdomain}.${var.dns_zone}",
        "https://${var.geoweb_subdomain}.${var.dns_zone}"
      ]
      post_logout_redirect_uris = "https://${var.dev_portal_subdomain}.${var.dns_zone}##https://${var.geoweb_subdomain}.${var.dns_zone}"
    })
  }
}

resource "kubernetes_secret" "keycloak_admin_pw" {
  metadata {
    name      = "keycloak-admin-password"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
  data = {
    admin-password = local.keycloak_admin_password
  }
  type = "Opaque"
}

resource "helm_release" "keycloak" {
  name       = local.keycloak_helm_release_name
  namespace  = "keycloak"
  repository = "https://codecentric.github.io/helm-charts"
  chart      = "keycloakx"
  version    = "7.1.4"

  values = [
    templatefile("./templates/helm-values/keycloak-values-template.yaml", {
      db_secret_name               = kubernetes_secret.keycloak_postgresql.metadata[0].name
      db_secret_username_key       = "username"
      db_secret_password_key       = "password"
      kc_admin_username            = "admin"
      kc_admin_secret_name         = kubernetes_secret.keycloak_admin_pw.metadata[0].name
      kc_admin_secret_password_key = "admin-password"
      kc_realm_configmap_name      = kubernetes_config_map.realm-json.metadata[0].name
      cluster_issuer               = var.cluster_issuer
      hostname                     = "${var.keycloak_subdomain}.${var.dns_zone}",
      ip                           = var.load_balancer_ip
      repository                   = "quay.io/keycloak/keycloak"
      tag                          = "26.4.5"
    })
  ]
}

# Create ingress to redirect alternative domains to main domain
# About issue of permanent redirects with $redirect_uri 
# https://github.com/kubernetes/ingress-nginx/issues/11175
resource "kubectl_manifest" "cluster-keycloak-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace             = kubernetes_namespace.keycloak.metadata.0.name
      cluster_issuer        = var.cluster_issuer
      external_dns_hostname = join(",", [for name in local.alternative_hosted_zone_names : "${var.keycloak_subdomain}.${name}"])
      target_address        = var.load_balancer_ip
      permanent_redirect    = "https://${var.keycloak_subdomain}.${var.dns_zone}"
      redirect_domains      = [for name in local.alternative_hosted_zone_names : "${var.keycloak_subdomain}.${name}"]
      subdomain             = var.keycloak_subdomain
      cluster_name          = var.cluster_name
    }
  )
}

################################################################################

# Install Dev-portal
################################################################################
resource "kubernetes_namespace" "dev-portal" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = var.rancher_project_id
    }

    name = "dev-portal"
  }
}

resource "random_password" "dev-portal-password" {
  length = 32
}

# Create Secret for credentials
resource "kubernetes_secret" "dev-portal-secret-for-backend" {
  metadata {
    name      = "dev-portal-secret-for-backend"
    namespace = kubernetes_namespace.dev-portal.metadata.0.name
  }

  data = {
    "secrets.yaml" = yamlencode({
      "vault" = {
        "base_path"    = "${var.vault_mount_kv_base_path}/consumers"
        "secret_phase" = random_password.dev-portal-password.result
        "instances" = concat([
          {
            "name"  = upper(var.cluster_name)
            "token" = var.dev-portal_vault_token
            "url"   = "http://${var.vault_helm_release_name}-active.${var.vault_namespace_name}.svc.cluster.local:8200"
          }
          ],
          [for cluster in local.external_cluster_names : {
            "name"  = upper(cluster)
            "token" = local.external_vault_tokens[cluster]
            "url"   = "https://${var.vault_subdomain}.${cluster}.${var.dns_zone}"
          }]
        )
      }

      "apisix" = {
        "key_path"           = "$secret://vault/1/"
        "global_gateway_url" = "https://${var.apisix_subdomain}.${var.dns_zone}"
        "instances" = concat([
          {
            "name"          = upper(var.cluster_name)
            "admin_url"     = "http://${var.apisix_helm_release_name}-admin.${var.apisix_namespace_name}.svc.cluster.local:9180"
            "admin_api_key" = var.apisix_admin_api_key
          }
          ],
          [for cluster in local.external_cluster_names : {
            "name"          = upper(cluster)
            "admin_url"     = "https://admin-${var.apisix_subdomain}.${cluster}.${var.dns_zone}"
            "admin_api_key" = local.external_apisix_admin_api_keys[cluster]
          }]
        )
      }
      "keycloak" = {
        "url"           = "http://${local.keycloak_helm_release_name}-keycloakx-http.${kubernetes_namespace.keycloak.metadata.0.name}.svc.cluster.local"
        "realm"         = "${var.keycloak_realm_name}"
        "client_id"     = "dev-portal-api"
        "client_secret" = local.dev_portal_keycloak_secret
      }
    })
  }

  type = "Opaque"
}

resource "helm_release" "dev-portal" {
  name             = "dev-portal"
  repository       = "https://eumetnet.github.io/Dev-portal/"
  chart            = "dev-portal"
  version          = "1.14.4"
  namespace        = kubernetes_namespace.dev-portal.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./templates/helm-values/dev-portal-values-template.yaml", {
      cluster_issuer = var.cluster_issuer
      hostname       = "${var.dev_portal_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set = [
    {
      name  = "imageCredentials.username"
      value = "USERNAME"
    },
    {
      name  = "backend.image.tag"
      value = "sha-a13cd70"
    },
    {
      name  = "backend.secrets.secretName"
      value = kubernetes_secret.dev-portal-secret-for-backend.metadata.0.name
    },
    {
      name  = "frontend.image.tag"
      value = "sha-a13cd70"
    },
    {
      name  = "frontend.keycloak_logout_url"
      value = "https://${var.dev_portal_subdomain}.${var.dns_zone}"
    },
    {
      name  = "frontend.keycloak_url"
      value = "https://${var.keycloak_subdomain}.${var.dns_zone}"
    }
  ]

  set_sensitive = [{
    name  = "imageCredentials.password"
    value = local.dev_portal_registry_password
  }]

}

# Create ingress to redirect alternative domains to main domain
# About issue of permanent redirects with $redirect_uri 
# https://github.com/kubernetes/ingress-nginx/issues/11175
resource "kubectl_manifest" "cluster-dev-portal-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace             = kubernetes_namespace.dev-portal.metadata.0.name
      cluster_issuer        = var.cluster_issuer
      external_dns_hostname = join(",", [for name in local.alternative_hosted_zone_names : "${var.dev_portal_subdomain}.${name}"])
      target_address        = var.load_balancer_ip
      permanent_redirect    = "https://${var.dev_portal_subdomain}.${var.dns_zone}"
      redirect_domains      = [for name in local.alternative_hosted_zone_names : "${var.dev_portal_subdomain}.${name}"]
      subdomain             = var.dev_portal_subdomain
      cluster_name          = var.cluster_name
    }
  )
}
