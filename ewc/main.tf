provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
  
}

provider "rancher2" {
  api_url    = "https://rancher.my-domain.com"
  access_key = var.rancher_access_key
  secret_key = var.rancher_secret_key
}

################################################################################
# Get id of Rancher System project
################################################################################
data "rancher2_project" "System" {
    cluster_id = var.rancher_cluster_id
    name = "System"
}

################################################################################
# Install openstack-cinder-csi Plugin under System project
################################################################################
resource "kubernetes_namespace" "openstack-cinder-csi" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = data.rancher2_project.System.id
    }

    name = "openstack-cinder-csi"
  }
}
resource "helm_release" "csi-cinder" {
  name = "openstack-cinder-csi"
  repository = "https://kubernetes.github.io/cloud-provider-openstack"
  chart = "openstack-cinder-csi"
  version    = "2.30.0"
  namespace = kubernetes_namespace.openstack-cinder-csi.metadata.0.name
  create_namespace = false
  
  set {
    name = "storageClass.delete.isDefault"
    value = true
  }
  
  set {
    name = "secret.filename"
    value = "cloud-config"
  }
}

################################################################################
# Install ingress-nginx under System project
################################################################################
resource "kubernetes_namespace" "ingress-nginx" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = data.rancher2_project.System.id
    }

    name = "ingress-nginx"
  }
}
resource "helm_release" "ingress_nginx" {
  name = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart = "ingress-nginx"
  version    = "4.7.1"
  namespace = kubernetes_namespace.ingress-nginx.metadata.0.name
  create_namespace = false
  
  set {
    name = "controller.kind"
    value = "DaemonSet"
  }
  
  set {
    name = "controller.ingressClassResource.default"
    value = true
  }

# Needed for keycloak to work
  set {
    name = "controller.config.proxy-buffer-size"
    value = "256k"
  }
}

data "kubernetes_service" "ingress-nginx-controller" {
  metadata {
    name = "ingress-nginx-controller"
    namespace = kubernetes_namespace.ingress-nginx.metadata.0.name
  }

  depends_on = [helm_release.ingress_nginx]
}

################################################################################
# Install extneral-dns under System project
################################################################################
resource "kubernetes_namespace" "external-dns" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = data.rancher2_project.System.id
    }

    name = "external-dns"
  }
}
resource "helm_release" "external-dns" {
  name = "external-dns"
  repository = "https://charts.bitnami.com/bitnami"
  chart = "external-dns"
  version    = "6.23.6"
  namespace = kubernetes_namespace.external-dns.metadata.0.name
  create_namespace = false
  
  set {
    name = "policy"
    value = "sync"
  }
  
  set {
    name = "controller.ingressClassResource.default"
    value = true
  }

  set {
    name = "aws.credentials.accessKey"
    value = var.route53_access_key

  }

  set {
    name = "aws.credentials.secretKey"
    value = var.route53_secret_key

  }

  set_list {
    name = "zoneIdFilters"
    value = [var.route53_zone_id_filter]
  }
}

################################################################################
# Install cert-manager under System project
################################################################################
resource "kubernetes_namespace" "cert-manager" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = data.rancher2_project.System.id
    }

    name = "cert-manager"
  }
}
resource "helm_release" "cert-manager" {
  name = "cert-manager"
  repository = "https://charts.jetstack.io/"
  chart = "cert-manager"
  version    = "1.11.5 "
  namespace = kubernetes_namespace.cert-manager.metadata.0.name
  create_namespace = false
  
  set {
    name = "installCRDs"
    value = true
  }
  
  set {
    name = "ingressShim.defaultACMEChallengeType"
    value = "dns01"
  }

  set {
    name = "ingressShim.defaultACMEDNS01ChallengeProvider"
    value = "route53"
  }

  set {
    name = "ingressShim.defaultIssuerKind"
    value = "ClusterIssuer"
  }

  set {
    name = "ingressShim.letsencrypt-prod"
    value = "route53"
  }
}

resource "kubernetes_secret" "acme-route53-secret" {
  metadata {
    name = "acme-route53"
    namespace = kubernetes_namespace.cert-manager.metadata.0.name
  }

  data = {
    secret-access-key = var.route53_secret_key
  }

  type = "Opaque"
}

resource "kubernetes_manifest" "clusterissuer_letsencrypt_prod" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind" = "ClusterIssuer"
    "metadata" = {
      "name" = "letsencrypt-prod"
    }
    "spec" = {
      "acme" = {
        "email" = var.email_cert_manager
        "privateKeySecretRef" = {
          "name" = "letsencrypt-prod"
        }
        "server" = "https://acme-v02.api.letsencrypt.org/directory"
        "solvers" = [
          {
            "dns01" = {
              "route53" = {
                "accessKeyID" = var.rancher_access_key
                "region" = "eu-central-1"
                "secretAccessKeySecretRef" = {
                  "key" = "secret-access-key"
                  "name" = kubernetes_secret.acme-route53-secret.metadata.0.name
                }
              }
            }
            "selector" = {
              "dnsZones" = [var.dns_zone]
            }
          },
        ]
      }
    }
  }
  depends_on = [ helm_release.cert-manager ]
}
