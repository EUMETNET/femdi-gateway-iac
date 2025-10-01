resource "kubernetes_namespace" "geoweb" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = var.rancher_project_id
    }

    name = "geoweb"
  }
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
    templatefile("./templates/helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set = [
    {
      name  = "versions.frontend"
      value = "2025-09-24_12-03_7e3c2bd0"
    },
    {
      name  = "frontend.url"
      value = "${var.geoweb_subdomain}.${var.dns_zone}"
    },
    {
      name  = "frontend.env.GW_AUTH_LOGOUT_URL"
      value = "https://${var.geoweb_subdomain}.${var.dns_zone}"
    },
    {
      name  = "frontend.env.GW_AUTH_TOKEN_URL"
      value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/token"
    },
    {
      name  = "frontend.env.GW_AUTH_LOGIN_URL"
      value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/auth?client_id={client_id}&response_type=code&scope=email+openid&redirect_uri={app_url}/code&state={state}&code_challenge={code_challenge}&code_challenge_method=S256"
    },
    {
      name  = "frontend.env.GW_APP_URL"
      value = "https://${var.geoweb_subdomain}.${var.dns_zone}"
    },
    {
      name  = "frontend.env.GW_AUTH_ROLE_CLAIM_NAME"
      value = "groups"
    },
    {
      name  = "frontend.env.GW_AUTH_ROLE_CLAIM_VALUE_PRESETS_ADMIN"
      value = "Admin"
    },
    {
      name  = "frontend.env.GW_FEATURE_APP_TITLE"
      value = "MeteoGate Data Explorer"
    },
    {
      name  = "frontend.env.GW_AUTH_CLIENT_ID"
      value = "frontend"
    },
    {
      name  = "frontend.env.GW_PRESET_BACKEND_URL"
      value = "https://${var.geoweb_subdomain}.${var.dns_zone}${local.presets_backend_base_path}"
    },
    {
      name  = "frontend.env.GW_DATA_EXPLORER_CONFIGURATION_FILENAME"
      value = "dataexplorerPresets.json"
    },
    {
      name  = "frontend.env.GW_DATA_EXPLORER_BUTTON_ON_MAP"
      value = "true"
      type  = "string"
    },
    {
      name  = "frontend.env.GW_FEATURE_ENABLE_SPECIAL_THEMES"
      value = "true"
      type  = "string"
    },
    {
      name  = "frontend.env.GW_DEFAULT_THEME"
      value = "eumetnetTheme"
    },
    {
      name  = "frontend.env.GW_LOCATION_BASE_URL"
      value = "https://${var.geoweb_subdomain}.${var.dns_zone}${local.location_backend_base_path}"
    },
    {
      name  = "frontend.env.GW_INITIAL_WORKSPACE_PRESET"
      value = "46a7beec-9d22-11f0-a3fc-9e27ba5f6c02"
    }
  ]
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
    templatefile("./templates/helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set = [
    {
      name  = "presets.url"
      value = "${var.geoweb_subdomain}.${var.dns_zone}"
    },
    {
      name  = "presets.path"
      value = local.presets_backend_base_path
    },
    #set {
    #  name  = "presets.useCustomWorkspacePresets"
    #  value = true
    #}
    #
    #set {
    #  name  = "presets.customConfigurationFolderPath"
    #  value = "local"
    #}
    #
    #set {
    #  name  = "presets.customPresetsS3bucketName"
    #  value = "explorer-custom-presets"
    #}
    {
      name  = "presets.nginx.ALLOW_ANONYMOUS_ACCESS"
      value = "TRUE"
      type  = "string" # Ensure the value is treated as a string
    },
    {
      name  = "presets.nginx.JWKS_URI"
      value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}/protocol/openid-connect/certs"
    },
    {
      name  = "presets.nginx.AUD_CLAIM_VALUE"
      value = "account"
    },
    {
      name  = "presets.nginx.ISS_CLAIM"
      value = "iss"
    },
    {
      name  = "presets.nginx.ISS_CLAIM_VALUE"
      value = "https://${var.keycloak_subdomain}.${var.dns_zone}/realms/${var.keycloak_realm_name}"
    },
    {
      name  = "presets.nginx.GEOWEB_ROLE_CLAIM_NAME"
      value = "groups"
    },
    {
      name  = "presets.nginx.GEOWEB_ROLE_CLAIM_VALUE_PRESETS_ADMIN"
      value = "Admin"
    }
  ]
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
    templatefile("./templates/helm-values/geoweb-values-template.yaml", {
      cluster_issuer = var.cluster_issuer,
      hostname       = "${var.geoweb_subdomain}.${var.dns_zone}",
      ip             = var.load_balancer_ip
    })
  ]

  set = [
    {
      name  = "location.url"
      value = "${var.geoweb_subdomain}.${var.dns_zone}"
    },
    {
      name  = "location.path"
      value = local.location_backend_base_path
    }
  ]
}

# Create ingress to redirect alternative domains to main domain
resource "kubectl_manifest" "cluster-geoweb-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace             = kubernetes_namespace.geoweb.metadata.0.name
      cluster_issuer        = var.cluster_issuer
      external_dns_hostname = join(",", [for name in local.alternative_hosted_zone_names : "${var.geoweb_subdomain}.${name}"])
      target_address        = var.load_balancer_ip
      permanent_redirect    = "https://${var.geoweb_subdomain}.${var.dns_zone}$request_uri"
      redirect_domains      = [for name in local.alternative_hosted_zone_names : "${var.geoweb_subdomain}.${name}"]
      subdomain             = var.geoweb_subdomain
      cluster_name          = var.cluster_name
    }
  )
}
