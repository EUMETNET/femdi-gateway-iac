################################################################################
# Install Keycloak 
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
  postgres_db_user           = "bn_keycloak"      # default from Helm chart
  keycloak_helm_release_name = "keycloak"
}

#resource "random_password" "keycloak-dev-portal-secret" {
#  length  = 32
#  special = false
#}

# Create configmap for realm json
resource "kubernetes_config_map" "realm-json" {
  metadata {
    name      = "realm-json"
    namespace = kubernetes_namespace.keycloak.metadata.0.name
  }
  data = {
    "realm.json" = templatefile("./keycloak-realm/realm-export.json", {
      dev_portal_api_secret    = jsonencode(local.dev_portal_keycloak_secret)
      google_idp_client_secret = local.google_idp_client_secret
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

#TODO: Add HPA
#TODO: Consider managing the secrets in self managed kubernetes_secret instead of using Helm chart generated secret
#      Could not make self managed secret work reliably. Possible cause of this https://github.com/bitnami/charts/issues/18014
resource "helm_release" "keycloak" {
  name             = local.keycloak_helm_release_name
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "keycloak"
  version          = "21.1.2"
  namespace        = kubernetes_namespace.keycloak.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./templates/helm-values/keycloak-values-template.yaml", {
      cluster_issuer = var.cluster_issuer
      hostname       = "${var.keycloak_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  # Needed for tls termination at ingress
  # See: https://github.com/bitnami/charts/tree/main/bitnami/keycloak#use-with-ingress-offloading-ssl
  set = [
    {
      name  = "proxy"
      value = "edge"
    },
    {
      name  = "auth.adminUser"
      value = "admin"
    },
    {
      name  = "postgresql.auth.username"
      value = local.postgres_db_user
    },
    {
      name  = "postgresql.auth.database"
      value = local.postgres_db_name
    },
    # Needed for configmap realm import
    # See: https://github.com/bitnami/charts/issues/5178#issuecomment-765361901
    {
      name  = "extraStartupArgs"
      value = "--import-realm"

    },
    {
      name  = "extraVolumeMounts[0].name"
      value = "config"
    },
    {
      name  = "extraVolumeMounts[0].mountPath"
      value = "/opt/bitnami/keycloak/data/import"
    },
    {
      name  = "extraVolumeMounts[0].readOnly"
      value = true
    },
    {
      name  = "extraVolumes[0].name"
      value = "config"
    },
    {
      name  = "extraVolumes[0].configMap.name"
      value = kubernetes_config_map.realm-json.metadata[0].name
    },
    {
      name  = "extraVolumes[0].configMap.items[0].key"
      value = "realm.json"
    },
    {
      name  = "extraVolumes[0].configMap.items[0].path"
      value = "realm.json"
    },
    #Statefulset params
    {
      name  = "replicaCount"
      value = local.keycloak_replica_count
    }
  ]

  set_sensitive = [{
    name  = "auth.adminPassword"
    value = local.keycloak_admin_password
  }]

}

# Create ingress to redirect alternative domains to main domain
resource "kubectl_manifest" "cluster-keycloak-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace                     = kubernetes_namespace.keycloak.metadata.0.name
      cluster_issuer                = var.cluster_issuer
      external_dns_hostname         = join(",", [for name in local.alternative_hosted_zone_names : "${var.keycloak_subdomain}.${var.cluster_name}.${name}"])
      target_address                = var.load_balancer_ip
      permanent_redirect            = "https://${var.keycloak_subdomain}.${var.cluster_name}.${var.dns_zone}$request_uri"
      alternative_hosted_zone_names = local.alternative_hosted_zone_names
      subdomain                     = var.keycloak_subdomain
      cluster_name                  = var.cluster_name
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
        "url"           = "http://${local.keycloak_helm_release_name}.${kubernetes_namespace.keycloak.metadata.0.name}.svc.cluster.local"
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
  version          = "1.14.3"
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
      value = "sha-023ade0"
    },
    {
      name  = "backend.secrets.secretName"
      value = kubernetes_secret.dev-portal-secret-for-backend.metadata.0.name
    },
    {
      name  = "frontend.image.tag"
      value = "sha-be9fda5"
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
resource "kubectl_manifest" "cluster-dev-portal-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace                     = kubernetes_namespace.dev-portal.metadata.0.name
      cluster_issuer                = var.cluster_issuer
      external_dns_hostname         = join(",", [for name in local.alternative_hosted_zone_names : "${var.dev_portal_subdomain}.${var.cluster_name}.${name}"])
      target_address                = var.load_balancer_ip
      permanent_redirect            = "https://${var.dev_portal_subdomain}.${var.cluster_name}.${var.dns_zone}$request_uri"
      alternative_hosted_zone_names = local.alternative_hosted_zone_names
      subdomain                     = var.dev_portal_subdomain
      cluster_name                  = var.cluster_name
    }
  )
}
