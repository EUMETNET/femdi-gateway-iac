resource "kubernetes_namespace" "geoweb" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = var.rancher_project_id
    }

    name = "geoweb"
  }
}

locals {
  presets_backend_base_path  = "/presets"
  location_backend_base_path = "/location-backend"
}

################################################################################

# Frontend application
################################################################################
resource "helm_release" "geoweb-frontend" {
  name             = "geoweb-frontend"
  repository       = "https://fmidev.github.io/helm-charts/"
  chart            = "geoweb-frontend"
  version          = "3.20.0"
  namespace        = kubernetes_namespace.geoweb.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set {
    name  = "versions.frontend"
    value = "2025-08-11_10-01_8686a987"
  }

  set {
    name  = "frontend.url"
    value = "${var.geoweb_subdomain}.${var.dns_zone}"
  }

  set {
    name  = "frontend.env.GW_AUTH_LOGOUT_URL"
    value = "https://${var.geoweb_subdomain}.${var.dns_zone}"
  }

  set {
    name  = "frontend.env.GW_AUTH_TOKEN_URL"
    value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/token"
  }

  set {
    name  = "frontend.env.GW_AUTH_LOGIN_URL"
    value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/auth?client_id={client_id}&response_type=code&scope=email+openid&redirect_uri={app_url}/code&state={state}&code_challenge={code_challenge}&code_challenge_method=S256"
  }

  set {
    name  = "frontend.env.GW_APP_URL"
    value = "https://${var.geoweb_subdomain}.${var.dns_zone}"
  }

  set {
    name  = "frontend.env.GW_AUTH_ROLE_CLAIM_NAME"
    value = "groups"
  }

  set {
    name  = "frontend.env.GW_AUTH_ROLE_CLAIM_VALUE_PRESETS_ADMIN"
    value = "Admin"
  }

  set {
    name  = "frontend.env.GW_FEATURE_APP_TITLE"
    value = "MeteoGate Data Explorer"
  }

  set {
    name  = "frontend.env.GW_AUTH_CLIENT_ID"
    value = "frontend"
  }

  set {
    name  = "frontend.env.GW_PRESET_BACKEND_URL"
    value = "https://${var.geoweb_subdomain}.${var.dns_zone}${local.presets_backend_base_path}"
  }

  set {
    name  = "frontend.env.GW_DATAEXPLORER_CONFIGURATION_FILENAME"
    value = "dataexplorerPresets.json"
  }

  set {
    name  = "frontend.env.GW_DATAEXPLORER_BUTTON_ON_MAP"
    value = "true"
    type  = "string"
  }

  set {
    name  = "frontend.env.GW_LOCATION_BASE_URL"
    value = "https://${var.geoweb_subdomain}.${var.dns_zone}${local.location_backend_base_path}"
  }

  set {
    name  = "frontend.env.GW_INITIAL_WORKSPACE_PRESET"
    value = "a0a3a296-76ab-11f0-aca7-123d7660ed3b"
  }
}

################################################################################

# Presets backend service
################################################################################
resource "helm_release" "geoweb-presets-backend" {
  name             = "geoweb-presets-backend"
  repository       = "https://fmidev.github.io/helm-charts/"
  chart            = "geoweb-presets-backend"
  version          = "2.15.0"
  namespace        = kubernetes_namespace.geoweb.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set {
    name  = "presets.url"
    value = "${var.geoweb_subdomain}.${var.dns_zone}"
  }

  set {
    name  = "presets.path"
    value = local.presets_backend_base_path
  }

  set {
    name  = "presets.nginx.ALLOW_ANONYMOUS_ACCESS"
    value = "TRUE"
    type  = "string" # Ensure the value is treated as a string
  }

  set {
    name  = "presets.nginx.JWKS_URI"
    value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/certs"
  }

  set {
    name  = "presets.nginx.AUD_CLAIM_VALUE"
    value = "account"
  }

  set {
    name  = "presets.nginx.ISS_CLAIM"
    value = "iss"
  }

  set {
    name  = "presets.nginx.ISS_CLAIM_VALUE"
    value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}"
  }

  set {
    name  = "presets.nginx.GEOWEB_ROLE_CLAIM_NAME"
    value = "groups"
  }

  set {
    name  = "presets.nginx.GEOWEB_ROLE_CLAIM_VALUE_PRESETS_ADMIN"
    value = "Admin"
  }
}

################################################################################

# Location backend service
################################################################################
resource "helm_release" "geoweb-location-backend" {
  name             = "geoweb-location-backend"
  repository       = "https://fmidev.github.io/helm-charts/"
  chart            = "geoweb-location-backend"
  version          = "1.1.0"
  namespace        = kubernetes_namespace.geoweb.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set {
    name  = "location.url"
    value = "${var.geoweb_subdomain}.${var.dns_zone}"
  }

  set {
    name  = "location.path"
    value = local.location_backend_base_path
  }
}
