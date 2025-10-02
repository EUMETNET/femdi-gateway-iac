
################################################################################

# Install Monitoring for Rancher
################################################################################

# Locals for ServiceMonitors
locals {
  ingress-nginx-servicemonitor-manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "ServiceMonitor"
    "metadata" = {
      "labels" = {
        "release" = "prometheus"
      }
      "name"      = "ingress-nginx-controller"
      "namespace" = "kube-system"
    }
    "spec" = {
      "endpoints" = [
        {
          "interval" = "30s"
          "port"     = "metrics"
        },
      ]
      "namespaceSelector" = {
        "matchNames" = [
          "kube-system",
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/component" = "controller"
          "app.kubernetes.io/instance"  = "ingress-nginx"
          "app.kubernetes.io/name"      = "ingress-nginx"
        }
      }
    }
  }

}
data "rancher2_project" "System" {
  provider   = rancher2
  cluster_id = local.rancher_cluster_id
  name       = "System"
}

# alertmanagerConfigMatcherStrategy:
#    type: None
#
# Without this ^ we need to define alertmanagerConfigs per namespace
# https://github.com/rancher/rancher/issues/41585
# https://github.com/prometheus-operator/prometheus-operator/issues/3737
resource "rancher2_app_v2" "rancher-monitoring" {
  cluster_id = local.rancher_cluster_id
  name       = "rancher-monitoring"
  namespace  = "cattle-monitoring-system"
  project_id = data.rancher2_project.System.id
  repo_name  = "rancher-charts"
  chart_name = "rancher-monitoring"
  values     = <<EOF
extraEnv:
  - name: "CATTLE_PROMETHEUS_METRICS"
    value: "true"
grafana:
  grafana.ini:
    security:
      angular_support_enabled: true
alertmanager:
  alertmanagerSpec:
    alertmanagerConfigMatcherStrategy:
      type: None
EOF
}

# Create ingress-nginx serviceMonitor manually because we don't want to upgrade the chart.
# This should work as the EWC RKE2 default install for ingress-nginx has monitoring enable but not the serviceMonitor.
# See: https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/#re-configure-ingress-nginx-controller
resource "kubectl_manifest" "ingress_nginx_controller-servicemonitor" {
  yaml_body  = yamlencode(local.ingress-nginx-servicemonitor-manifest)
  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Create configmap for Apisix grafana dashboard
resource "kubernetes_config_map" "dashboard-apisix" {
  metadata {
    name      = "dashboard-apisix"
    namespace = "cattle-dashboards"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "dashboard-apisix.json" = file("./grafana-dashboards/apisix-dashboard.json")
  }

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Create configmap for NGINX Ingress controller grafana dashboard
resource "kubernetes_config_map" "dashboard-nginx-ingress-controller" {
  metadata {
    name      = "dashboard-nginx-ingress-controller"
    namespace = "cattle-dashboards"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "dashboard-nginx-ingress-controller.json" = file("./grafana-dashboards/ingress-nginx-dashboard.json")
  }

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Create configmap for NGINX request-handling-performance grafana dashboard
resource "kubernetes_config_map" "dashboard-request-handling-performance" {
  metadata {
    name      = "dashboard-request-handling-performance"
    namespace = "cattle-dashboards"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "dashboard-request-handling-performance.json" = file("./grafana-dashboards/reguest-handling-performance-dashboard.json")
  }

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Vault Needs its own policy and token for Promtheus metrics
resource "vault_policy" "prometheus" {
  name = "prometheus"

  policy = <<EOT
path "sys/metrics" {
  capabilities = ["read", "list"]
}
EOT

  depends_on = [module.ewc-vault-init]
}

resource "vault_token" "prometheus" {
  policies  = [vault_policy.prometheus.name]
  period    = "768h"
  renewable = true
  no_parent = true

  depends_on = [module.ewc-vault-init]
}

resource "kubernetes_secret" "token-secret-for-prometheus" {
  metadata {
    name      = "prometheus-token"
    namespace = "vault"
  }

  data = {
    "token" = vault_token.prometheus.client_token
  }

  type = "Opaque"
}

locals {
  vault-servicemonitor-manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "ServiceMonitor"
    "metadata" = {
      "labels" = {
        "release" = "prometheus"
      }
      "name"      = "vault"
      "namespace" = "vault"
    }
    "spec" = {
      "endpoints" = [
        {

          "authorization" = {
            "type" = "Bearer"
            "credentials" = {
              "name" = kubernetes_secret.token-secret-for-prometheus.metadata.0.name
              "key"  = "token"
            }
          }
          "interval" = "30s"
          "params" = {
            "format" = [
              "prometheus",
            ]
          }
          "path"          = "/v1/sys/metrics"
          "port"          = "https"
          "scheme"        = "http"
          "scrapeTimeout" = "10s"
          "tlsConfig" = {
            "insecureSkipVerify" = true
          }
        },
      ]
      "namespaceSelector" = {
        "matchNames" = [
          "vault",
        ]
      }
      "selector" = {
        "matchLabels" = {
          "app.kubernetes.io/instance" = "vault"
          "app.kubernetes.io/name"     = "vault"
          "vault-active"               = "true"
        }
      }
    }
  }
}

# Create Vault ServiceMonitor manually so we don't have to install prometheus-operator
# before Vault helm chart
resource "kubectl_manifest" "vault_servicemonitor" {
  yaml_body  = yamlencode(local.vault-servicemonitor-manifest)
  depends_on = [rancher2_app_v2.rancher-monitoring]
}

# Create configmap for Vault grafana dashboard
resource "kubernetes_config_map" "dashboard-vault" {
  metadata {
    name      = "dashboard-vault"
    namespace = "cattle-dashboards"
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "vault-dashboard.json" = file("./grafana-dashboards/vault-dashboard.json")
  }

  depends_on = [rancher2_app_v2.rancher-monitoring]
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = rancher2_project.gateway.id
    }
    name = "grafana"
  }
}

resource "kubernetes_secret" "auth_generic_oauth" {
  metadata {
    name      = "auth-generic-oauth-secret"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }
  type = "Opaque"
  data = {
    client_secret = "n6IRuCO6P8fdYCdJCgpGyzxy0RxcA5RK"
  }
}

resource "helm_release" "standalone_grafana" {
  name       = "grafana"
  namespace  = kubernetes_namespace.grafana.metadata[0].name
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  version    = "9.4.5" # just to test out
  values = [
    <<EOF
replicaCount: 1
adminUser: admin
adminPassword: yourpassword
service:
  type: ClusterIP
  port: 80
ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: ${module.ewc-vault-init.cluster_issuer}
    external-dns.alpha.kubernetes.io/hostname: "grafana.${local.dns_zone}"
    external-dns.alpha.kubernetes.io/target: ${module.ewc-vault-init.load_balancer_ip}
    kubernetes.io/tls-acme: "true"
  hosts:
    - "grafana.${local.dns_zone}"
  tls:
    - hosts:
        - "grafana.${local.dns_zone}"
      secretName: grafana-tls
extraSecretMounts:
  - name: auth-generic-oauth-secret-mount
    secretName: auth-generic-oauth-secret
    defaultMode: 0440
    mountPath: /etc/secrets/auth_generic_oauth
    readOnly: true
env:
  GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET_FILE: /etc/secrets/auth_generic_oauth/client_secret
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        uid: prometheus
        url: http://rancher-monitoring-prometheus.cattle-monitoring-system.svc.cluster.local:9090
        access: proxy
        isDefault: true
sidecar:
  dashboards:
    enabled: true
    label: grafana_dashboard
    folder: /var/lib/grafana/dashboards

dashboardProviders:
  dashboardproviders.yaml:
    apiVersion: 1
    providers:
      - name: 'default'
        orgId: 1
        folder: ''
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards
grafana.ini:
  server:
    root_url: https://grafana.${local.dns_zone}
  security:
    angular_support_enabled: true
  auth.generic_oauth:
    enabled: true
    name: Keycloak
    allow_sign_up: true
    scopes: openid profile email
    client_id: grafana-oauth
    client_secret: $__file{/etc/secrets/auth_generic_oauth/client_secret}
    auth_url: https://keycloak.meteogate.eu/realms/meteogate/protocol/openid-connect/auth
    token_url: https://keycloak.meteogate.eu/realms/meteogate/protocol/openid-connect/token
    api_url: https://keycloak.meteogate.eu/realms/meteogate/protocol/openid-connect/userinfo
    role_attribute_path: "contains(groups[*], 'Admin') && 'Admin' || 'Viewer'"
    login_attribute_path: preferred_username
    email_attribute_path: email
    name_attribute_path: name
    allow_assign_grafana_admin: false
EOF
  ]

}

# Create configmap for Apisix grafana dashboard
resource "kubernetes_config_map" "dashboard-apisix-standalone-grafana" {
  metadata {
    name      = "dashboard-apisix"
    namespace = kubernetes_namespace.grafana.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }
  data = {
    "dashboard-apisix.json" = file("./grafana-dashboards/apisix-dashboard.json")
  }

  depends_on = [helm_release.standalone_grafana]
}
