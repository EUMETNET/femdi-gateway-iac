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
  api_url   = var.rancher_api_url
  token_key = var.rancher_token
  # Remove when EWC fixes their DNS
  insecure = true
}

################################################################################
# Get id of Rancher System project
################################################################################
data "rancher2_project" "System" {
  provider   = rancher2
  cluster_id = var.rancher_cluster_id
  name       = "System"
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
  name             = "openstack-cinder-csi"
  repository       = "https://kubernetes.github.io/cloud-provider-openstack"
  chart            = "openstack-cinder-csi"
  version          = "2.30.0"
  namespace        = kubernetes_namespace.openstack-cinder-csi.metadata.0.name
  create_namespace = false

  set {
    name  = "storageClass.delete.isDefault"
    value = true
  }

  set {
    name  = "secret.filename"
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
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.7.1"
  namespace        = kubernetes_namespace.ingress-nginx.metadata.0.name
  create_namespace = false

  set {
    name  = "controller.kind"
    value = "DaemonSet"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = true
  }

  # Needed for keycloak to work
  set {
    name  = "controller.config.proxy-buffer-size"
    value = "256k"
  }
}

data "kubernetes_service" "ingress-nginx-controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = kubernetes_namespace.ingress-nginx.metadata.0.name
  }

  depends_on = [helm_release.ingress_nginx]
}

################################################################################
# Install external-dns under System project
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
  name             = "external-dns"
  repository       = "https://charts.bitnami.com/bitnami"
  chart            = "external-dns"
  version          = "6.23.6"
  namespace        = kubernetes_namespace.external-dns.metadata.0.name
  create_namespace = false

  set {
    name  = "policy"
    value = "upsert-only"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = true
  }

  set {
    name  = "aws.credentials.accessKey"
    value = var.route53_access_key

  }

  set {
    name  = "aws.credentials.secretKey"
    value = var.route53_secret_key

  }

  set_list {
    name  = "zoneIdFilters"
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
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io/"
  chart            = "cert-manager"
  version          = "1.11.5"
  namespace        = kubernetes_namespace.cert-manager.metadata.0.name
  create_namespace = false

  set {
    name  = "installCRDs"
    value = true
  }

  set {
    name  = "ingressShim.defaultACMEChallengeType"
    value = "dns01"
  }

  set {
    name  = "ingressShim.defaultACMEDNS01ChallengeProvider"
    value = "route53"
  }

  set {
    name  = "ingressShim.defaultIssuerKind"
    value = "ClusterIssuer"
  }

  set {
    name  = "ingressShim.letsencrypt-prod"
    value = "route53"
  }
}

resource "kubernetes_secret" "acme-route53-secret" {
  metadata {
    name      = "acme-route53"
    namespace = kubernetes_namespace.cert-manager.metadata.0.name
  }

  data = {
    secret-access-key = var.route53_secret_key
  }

  type = "Opaque"
}

locals {
  clusterissuer_letsencrypt_prod_manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name"      = "letsencrypt-prod"
      "namespace" = kubernetes_namespace.cert-manager.metadata.0.name
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
                "accessKeyID" = var.route53_access_key
                "region"      = "eu-central-1"
                "secretAccessKeySecretRef" = {
                  "key"  = "secret-access-key"
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
}

resource "kubectl_manifest" "clusterissuer_letsencrypt_prod" {
  yaml_body  = yamlencode(local.clusterissuer_letsencrypt_prod_manifest)
  depends_on = [helm_release.cert-manager]

}



################################################################################
# Install vault
################################################################################
resource "kubernetes_namespace" "vault" {
  metadata {
    annotations = {
      "field.cattle.io/projectId" = var.vault_project_id
    }

    name = "vault"
  }
}

locals {
  vault_certificate_secret = "vault-certificates"
  vault_issuer_manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Issuer"
    "metadata" = {
      "name"      = "vault-selfsigned-issuer"
      "namespace" = kubernetes_namespace.vault.metadata.0.name
    }
    "spec" = {
      "selfSigned" = {}
    }
  }
  vault_certificate_manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "Certificate"
    "metadata" = {
      "name"      = local.vault_certificate_secret
      "namespace" = kubernetes_namespace.vault.metadata.0.name
    }
    "spec" = {
      "isCA"       = true
      "commonName" = "vault-ca"
      "secretName" = local.vault_certificate_secret
      "privateKey" = {
        "algorithm" = "ECDSA"
        "size"      = 256
      }
      "issuerRef" = {
        "group" = "cert-manager.io"
        "kind"  = "Issuer"
        "name"  = kubectl_manifest.vault-issuer.name
      }
      "dnsNames" = [
        "*.vault-internal",
        "*.vault-internal.${kubernetes_namespace.vault.metadata.0.name}",
        "*.vault-internal.${kubernetes_namespace.vault.metadata.0.name}.svc",
        "*.vault-internal.${kubernetes_namespace.vault.metadata.0.name}.svc.cluster.local",
      ]
    }
  }
}


resource "kubectl_manifest" "vault-issuer" {
  yaml_body  = yamlencode(local.vault_issuer_manifest)
  depends_on = [helm_release.cert-manager]
}

resource "kubectl_manifest" "vault-certificates" {
  yaml_body  = yamlencode(local.vault_certificate_manifest)
  depends_on = [helm_release.cert-manager, kubectl_manifest.vault-issuer]
}

resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.28.0"
  namespace        = kubernetes_namespace.vault.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/vault-values-template.yaml", {
      cluster_issuer           = kubectl_manifest.clusterissuer_letsencrypt_prod.name,
      hostname                 = "${var.vault_subdomain}.${var.dns_zone}",
      ip                       = data.kubernetes_service.ingress-nginx-controller.status[0].load_balancer[0].ingress[0].ip,
      vault_certificate_secret = local.vault_certificate_secret
      replicas                 = var.vault_replicas
      replicas_iterator        = range(var.vault_replicas)
    })
  ]


  depends_on = [helm_release.cert-manager, helm_release.external-dns,
  helm_release.ingress_nginx, helm_release.csi-cinder]

}

# Wait for vault container to be availible
resource "time_sleep" "wait_5_second" {
  create_duration = "5s"
  depends_on      = [helm_release.vault]
}

data "kubernetes_resource" "vault-pods-before" {
  count = var.vault_replicas

  api_version = "v1"
  kind        = "Pod"

  metadata {
    name      = "vault-${count.index}"
    namespace = kubernetes_namespace.vault.metadata.0.name
  }

  depends_on = [helm_release.vault, time_sleep.wait_5_second]
}

data "external" "vault-init" {
  program = [
    "bash",
    "./vault-init/vault-init.sh",
    var.kubeconfig_path,
    kubernetes_namespace.vault.metadata.0.name,
    join(" ", flatten([
      for pod in data.kubernetes_resource.vault-pods-before : [
        for condition in pod.object.status.conditions : condition.status
        if condition.type == "Ready"
      ]])
    ),
    var.vault_key_treshold
  ]

  depends_on = [helm_release.vault, time_sleep.wait_5_second, data.kubernetes_resource.vault-pods-before]

}

data "kubernetes_resource" "vault-pods-after" {
  count = var.vault_replicas

  api_version = "v1"
  kind        = "Pod"

  metadata {
    name      = "vault-${count.index}"
    namespace = kubernetes_namespace.vault.metadata.0.name
  }

  depends_on = [helm_release.vault, time_sleep.wait_5_second, data.kubernetes_resource.vault-pods-before, data.external.vault-init]
}
