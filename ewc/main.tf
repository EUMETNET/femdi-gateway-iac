provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }

}

provider "kubernetes" {
  config_path = var.kubeconfig_path

}

#Workaround for https://github.com/hashicorp/terraform-provider-kubernetes/issues/1367
provider "kubectl" {
  config_path = var.kubeconfig_path
}

provider "rancher2" {
  api_url   = data.aws_ssm_parameter.rancher_api_url.value
  token_key = var.rancher_token
  insecure  = var.rancher_insecure
}


provider "vault" {
  address = "https://${var.vault_subdomain}.${var.cluster_name}.${var.dns_zone}"
  token   = var.vault_token
}

provider "random" {
}

# Use restapi provider as http does not supprot PUT and Apisix needs PUT
provider "restapi" {
  uri                  = "https://admin-${data.aws_ssm_parameter.apisix_subdomain.value}.${var.cluster_name}.${var.dns_zone}/"
  write_returns_object = true

  headers = {
    "X-API-KEY"    = aws_ssm_parameter.apisix_admin_api_key.value
    "Content-Type" = "application/json"
  }

  create_method = "PUT"
  update_method = "PUT"
}

provider "aws" {
  profile = "ewc"
}

provider "aws" {
  alias   = "fmi"
  profile = "fmi_meteogate"
}

################################################################################
# Install Vault and it's policies and tokens
################################################################################

module "ewc-vault-init" {
  source = "./ewc-vault-init/"

  rancher_api_url    = data.aws_ssm_parameter.rancher_api_url.value
  rancher_token      = var.rancher_token
  rancher_cluster_id = data.aws_ssm_parameter.rancher_cluster_id.value
  kubeconfig_path    = var.kubeconfig_path
  cluster_name       = var.cluster_name

  apisix_subdomain       = data.aws_ssm_parameter.apisix_subdomain.value
  route53_access_key     = var.route53_access_key
  route53_secret_key     = var.route53_secret_key
  route53_zone_id_filter = var.route53_zone_id_filter
  dns_zone               = var.dns_zone

  email_cert_manager = data.aws_ssm_parameter.cert_manager_email.value

  vault_project_id    = rancher2_project.gateway.id
  vault_subdomain     = var.vault_subdomain
  vault_replicas      = var.vault_replicas
  vault_anti-affinity = var.vault_anti-affinity
  vault_key_treshold  = var.vault_key_treshold

}

locals {
  vault_mount_kv_base_path = "apisix"
}

# Vault configurations after initialization and bootsrap
resource "vault_mount" "apisix" {
  path        = local.vault_mount_kv_base_path
  type        = "kv"
  options     = { version = "1" }
  description = "Apisix secrets"

  depends_on = [module.ewc-vault-init]
}

resource "vault_jwt_auth_backend" "github" {
  description        = "JWT for github actions"
  path               = "github"
  oidc_discovery_url = "https://token.actions.githubusercontent.com"
  bound_issuer       = "https://token.actions.githubusercontent.com"

  depends_on = [module.ewc-vault-init]
}

resource "vault_auth_backend" "kubernetes" {
  type        = "kubernetes"
  description = "Kubernetes auth backend"

  depends_on = [module.ewc-vault-init]
}

resource "vault_kubernetes_auth_backend_config" "k8s_auth_config" {
  backend = vault_auth_backend.kubernetes.path

  # Use the internal Kubernetes API server URL for communication within the cluster.
  # This URL is automatically resolved by the Kubernetes DNS service to the internal IP address of the Kubernetes API server.
  # If the provided host doesn't work (403 response) in future you can check correct DNS search paths using:
  # kubectl run -it --rm --restart=Never busybox --image=busybox -- sh
  # cat /etc/resolv.conf

  kubernetes_host = "https://kubernetes.default.svc.kubernetes.local"

  # We can omit rest of params, e.g. CA certificate and token reviewer JWT as long as 
  # Vault and calling service are run in same k8s cluster
  # https://developer.hashicorp.com/vault/docs/auth/kubernetes#use-local-service-account-token-as-the-reviewer-jwt
}

resource "vault_policy" "apisix-global" {
  name = "apisix-global"

  policy = <<EOT
path "${local.vault_mount_kv_base_path}/consumers/*" {
  capabilities = ["read"]
}

EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_policy" "dev-portal-global" {
  name = "dev-portal-global"

  policy = <<EOT
path "${local.vault_mount_kv_base_path}/consumers/*" {
	capabilities = ["create", "read", "update", "patch", "delete", "list"]
}
EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_policy" "api-management-tool-gha" {
  name = "api-management-tool-gha"

  policy = <<EOT
path "${local.vault_mount_kv_base_path}/apikeys/*" { capabilities = ["read"] }
path "${local.vault_mount_kv_base_path}/urls" { capabilities = ["read"] }
path "${local.vault_mount_kv_base_path}/urls/*" { capabilities = ["read"] }
path "${local.vault_mount_kv_base_path}/admin/*" { capabilities = ["read"] }
path "${local.vault_mount_kv_base_path}/consumer_groups/*" { capabilities = ["read"] }
EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_policy" "take-snapshot" {
  name = "take-snapshot"

  policy = <<EOT
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}
EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_policy" "renew-token" {
  name = "renew-token"

  policy = <<EOT
path "auth/token/renew" {
  capabilities = ["update"]
}
EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_jwt_auth_backend_role" "api-management-tool-gha" {
  role_name  = "api-management-tool-gha"
  backend    = vault_jwt_auth_backend.github.path
  role_type  = "jwt"
  user_claim = "actor"
  bound_claims = {
    repository : "EUMETNET/api-management-tool-poc"
  }
  bound_audiences = ["https://github.com/EUMETNET/api-management-tool-poc"]
  token_policies  = [vault_policy.api-management-tool-gha.name]
  token_ttl       = 300

  depends_on = [module.ewc-vault-init]
}

resource "vault_kubernetes_auth_backend_role" "cron-job" {
  backend                          = vault_auth_backend.kubernetes.path
  role_name                        = "cron-job"
  bound_service_account_names      = [kubernetes_service_account.vault_jobs_service_account.metadata.0.name]
  bound_service_account_namespaces = [module.ewc-vault-init.vault_namespace_name]
  token_policies                   = [vault_policy.take-snapshot.name, vault_policy.renew-token.name]
  token_ttl                        = 300

  depends_on = [module.ewc-vault-init]
}

resource "vault_token" "apisix-global" {
  policies  = [vault_policy.apisix-global.name]
  period    = "768h"
  renewable = true
  no_parent = true

  depends_on = [module.ewc-vault-init]
}
resource "vault_token" "dev-portal-global" {
  policies  = [vault_policy.dev-portal-global.name]
  period    = "768h"
  renewable = true
  no_parent = true

  depends_on = [module.ewc-vault-init]
}

# Reference outputs from global project to get global AWS related values
data "terraform_remote_state" "global" {
  backend = "s3"
  config = {
    bucket  = "meteogate-iac-terraform-states"
    key     = "global/terraform.tfstate"
    region  = "eu-north-1"
    profile = "fmi_meteogate"
  }
}

################################################################################
# Install gateway apps
################################################################################
# Create project for gateway
resource "rancher2_project" "gateway" {
  name       = "gateway"
  cluster_id = data.aws_ssm_parameter.rancher_cluster_id.value
}

################################################################################

# Install Dev-portal and keycloak
################################################################################

module "dev-portal-init" {
  count = var.install_dev-portal ? 1 : 0

  source = "./dev-portal-init/"

  kubeconfig_path = var.kubeconfig_path

  dns_zone = var.dns_zone

  cluster_issuer   = module.ewc-vault-init.cluster_issuer
  load_balancer_ip = module.ewc-vault-init.load_balancer_ip

  rancher_project_id = rancher2_project.gateway.id

  cluster_name = var.cluster_name

  keycloak_subdomain      = var.keycloak_subdomain
  keycloak_admin_password = var.keycloak_admin_password
  keycloak_replicas       = var.keycloak_replicas
  keycloak_realm_name     = var.keycloak_realm_name

  dev-portal_subdomain         = var.dev-portal_subdomain
  dev-portal_registry_password = var.dev-portal_registry_password
  dev-portal_vault_token       = vault_token.dev-portal-global.client_token

  apisix_subdomain         = data.aws_ssm_parameter.apisix_subdomain.value
  apisix_admin_api_key     = aws_ssm_parameter.apisix_admin_api_key.value
  apisix_helm_release_name = local.apisix_helm_release_name
  apisix_namespace_name    = kubernetes_namespace.apisix.metadata.0.name

  vault_helm_release_name = module.ewc-vault-init.vault_helm_release_name
  vault_namespace_name    = module.ewc-vault-init.vault_namespace_name

  vault_mount_kv_base_path = local.vault_mount_kv_base_path

  google_idp_client_secret = var.google_idp_client_secret
  github_idp_client_secret = var.github_idp_client_secret

  backup_bucket_name       = data.terraform_remote_state.global.outputs.backup_bucket_name
  backup_bucket_access_key = data.terraform_remote_state.global.outputs.backup_aws_access_key_id
  backup_bucket_secret_key = data.terraform_remote_state.global.outputs.backup_aws_secret_access_key

  apisix_additional_instances = var.apisix_additional_instances
  vault_additional_instances  = var.vault_additional_instances

  geoweb_subdomain = var.geoweb_subdomain

}

################################################################################

# Install Geoweb
################################################################################

module "geoweb" {
  count  = var.install_geoweb ? 1 : 0
  source = "./geoweb/"

  dns_zone = var.dns_zone

  cluster_issuer   = module.ewc-vault-init.cluster_issuer
  load_balancer_ip = module.ewc-vault-init.load_balancer_ip

  rancher_project_id = rancher2_project.gateway.id

  geoweb_subdomain    = var.geoweb_subdomain
  keycloak_subdomain  = var.keycloak_subdomain
  keycloak_realm_name = var.keycloak_realm_name
}
################################################################################

# Misc global DNS records
################################################################################
module "global_dns" {
  count = var.manage_global_dns_records ? 1 : 0

  source = "./global-dns-records/"

  route53_zone_id_filter = var.route53_zone_id_filter
  observations_ip        = var.manage_global_dns_records ? var.observations_ip : ""
  radar_ip               = var.manage_global_dns_records ? var.radar_ip : ""
  root_ip                = var.manage_global_dns_records ? var.root_ip : ""
}

################################################################################

# Install Apisix
################################################################################
resource "kubernetes_namespace" "apisix" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = rancher2_project.gateway.id
    }

    name = "apisix"
  }
}

# ConfigMap for custom error pages
resource "kubernetes_config_map" "custom_error_pages" {
  metadata {
    name      = "custom-error-pages"
    namespace = kubernetes_namespace.apisix.metadata.0.name
  }
  data = {
    "apisix_error_429.html" = templatefile("../apisix/error_pages/apisix_error_429.html", {
      devportal_address = "${var.dev-portal_subdomain}.${var.dns_zone}"
    })
    "apisix_error_403.html" = templatefile("../apisix/error_pages/apisix_error_403.html", {
      devportal_address = "${var.dev-portal_subdomain}.${var.dns_zone}"
    })
  }
}

resource "kubernetes_config_map" "apisix_custom_plugins" {
  metadata {
    name      = "custom-plugins"
    namespace = kubernetes_namespace.apisix.metadata[0].name
  }

  data = {
    "dynamic-response-rewrite.lua" = file("../apisix/custom-plugins/dynamic-response-rewrite.lua")
  }
}

locals {
  apisix_helm_release_name = "apisix"
  apisix_etcd_host         = "http://${local.apisix_helm_release_name}-etcd.${kubernetes_namespace.apisix.metadata.0.name}.svc.cluster.local:2379"
  vault_host               = "http://${module.ewc-vault-init.vault_helm_release_name}-active.${module.ewc-vault-init.vault_namespace_name}.svc.cluster.local:8200"
}

resource "helm_release" "apisix" {
  name             = local.apisix_helm_release_name
  repository       = "https://charts.apiseven.com"
  chart            = "apisix"
  version          = "2.10.0"
  namespace        = kubernetes_namespace.apisix.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/apisix-values-template.yaml", {
      cluster_issuer = module.ewc-vault-init.cluster_issuer,
      hostname       = "${data.aws_ssm_parameter.apisix_subdomain.value}.${var.cluster_name}.${var.dns_zone}",
      ip             = module.ewc-vault-init.load_balancer_ip
    })
  ]

  set_sensitive {
    name  = "apisix.admin.credentials.admin"
    value = aws_ssm_parameter.apisix_admin_api_key.value
  }

  set_sensitive {
    name  = "apisix.admin.credentials.viewer"
    value = aws_ssm_parameter.apisix_admin_reader_api_key.value
  }

  set_list {
    name  = "apisix.admin.allow.ipList"
    value = split(",", data.aws_ssm_parameter.apisix_admin_api_ip_list.value)
  }

  # Autoscaling
  set {
    name  = "autoscaling.enabled"
    value = true

  }

  set {
    name  = "autoscaling.minReplicas"
    value = var.apisix_replicas

  }

  # Enable Prometheus
  set {
    name  = "apisix.prometheus.enabled"
    value = true
  }

  set {
    name  = "metrics.serviceMonitor.enabled"
    value = true
  }

  # Apisix vault integration
  # Does not work. See https://github.com/apache/apisix-helm-chart/issues/795
  # Replaced by data.http request after this
  #set {
  #  name  = "apisix.vault.enabled"
  #  value = true
  #}

  #set {
  #  name  = "apisix.vault.host"
  #  value = local.vault_host
  #}

  #set {
  #  name  = "apisix.vault.prefix"
  #  value = "${local.vault_mount_kv_base_path}/consumers"
  #}

  #set_sensitive {
  #  name  = "apisix.vault.token"
  #  value = vault_token.apisix-global.client_token
  #}

  # Custom error pages mount
  set {
    name  = "extraVolumeMounts[0].name"
    value = "custom-error-pages"

  }

  set {
    name  = "extraVolumeMounts[0].mountPath"
    value = "/custom/error-pages"

  }

  set {
    name  = "extraVolumeMounts[0].readOnly"
    value = true

  }

  set {
    name  = "extraVolumes[0].name"
    value = "custom-error-pages"

  }

  set {
    name  = "extraVolumes[0].configMap.name"
    value = kubernetes_config_map.custom_error_pages.metadata[0].name

  }

  set {
    name  = "extraVolumes[0].configMap.items[0].key"
    value = "apisix_error_403.html"

  }

  set {
    name  = "extraVolumes[0].configMap.items[0].path"
    value = "apisix_error_403.html"

  }

  set {
    name  = "extraVolumes[0].configMap.items[1].key"
    value = "apisix_error_429.html"

  }

  set {
    name  = "extraVolumes[0].configMap.items[1].path"
    value = "apisix_error_429.html"

  }

  #Custom error page nginx.conf
  set {
    name  = "apisix.nginx.configurationSnippet.httpStart"
    value = file("../apisix/error_values/httpStart")
  }

  set {
    name  = "apisix.nginx.configurationSnippet.httpSrv"
    value = file("../apisix/error_values/httpSrv")
  }

  # Trust container's CA for Vault and other outbound CA requests
  set {
    name  = "apisix.nginx.configurationSnippet.httpEnd"
    value = "lua_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;"

  }

  # Custom plugins
  set_list {
    name  = "apisix.plugins"
    value = ["prometheus", "real-ip", "key-auth", "cors", "proxy-rewrite", "consumer-restriction", "response-rewrite", "limit-req", "limit-count", "serverless-pre-function"]
  }

  set {
    name  = "apisix.customPlugins.enabled"
    value = true
  }

  set {
    name  = "apisix.customPlugins.luaPath"
    value = "/opt/custom-plugins/?.lua;/opt/custom-plugins/apisix/plugins/?.lua"
  }

  set {
    name  = "apisix.customPlugins.plugins[0].name"
    value = "dynamic-response-rewrite"
  }

  set {
    name  = "apisix.customPlugins.plugins[0].configMap.name"
    value = kubernetes_config_map.apisix_custom_plugins.metadata[0].name
  }

  set {
    name  = "apisix.customPlugins.plugins[0].configMap.mounts[0].key"
    value = "dynamic-response-rewrite.lua"
  }

  set {
    name  = "apisix.customPlugins.plugins[0].configMap.mounts[0].path"
    value = "/opt/custom-plugins/apisix/plugins/dynamic-response-rewrite.lua"
  }

  # etcd config
  set {
    name  = "etcd.replicaCount"
    value = var.apisix_etcd_replicas
  }

  lifecycle {
    precondition {
      condition = alltrue([
        for i in split(",", data.aws_ssm_parameter.apisix_admin_api_ip_list.value) :
        can(cidrnetmask(i))
      ])
      error_message = "Given APISIX admin API IP list is not a valid list of CIDR-blocks"
    }
  }

  # Need connection to vault and Installs ServiceMonitor for scraping metrics
  depends_on = [module.ewc-vault-init, rancher2_app_v2.rancher-monitoring]

}

# Wait for Apisix before doing a PUT-request
resource "time_sleep" "wait_apisix" {
  create_duration = "10s"
  depends_on      = [helm_release.apisix]
}

locals {
  apisix_secret_put_body = {
    uri    = local.vault_host
    prefix = "${local.vault_mount_kv_base_path}/consumers"
    token  = vault_token.apisix-global.client_token
  }
}

# Needed for Apisix Vault integration as the Helm chart apisix.vault.enabled does nothing
resource "restapi_object" "apsisix_secret_put" {
  path         = "/apisix/admin/secrets/vault/{id}"
  id_attribute = "1"
  object_id    = "1"
  data         = jsonencode(local.apisix_secret_put_body)

  depends_on = [time_sleep.wait_apisix, helm_release.apisix]
}

# Enable prometheus and real-ip plugins for APISIX
# Prometheus for observability and metrics scraping
# Real-ip plugin to limit the unauthenticated requests based on client IP address
resource "restapi_object" "apisix_global_rules_config" {
  path         = "/apisix/admin/global_rules"
  id_attribute = "1"
  object_id    = "1"
  data = jsonencode({
    id = "1",
    plugins = {
      "prometheus" = {}
      "real-ip" = {
        source            = "http_x_real_ip",
        trusted_addresses = split(",", data.aws_ssm_parameter.ingress_nginx_private_subnets.value)
      }
    }
  })

  depends_on = [time_sleep.wait_apisix, helm_release.apisix]
}
