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
  insecure  = var.rancher_insecure
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
# Query ingress-nginx load balancer's IP
################################################################################
data "kubernetes_service" "ingress-nginx-controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "kube-system"
  }

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

  # Global APISIX subdomain handled separately
  set_list {
    name  = "excludeDomains"
    value = ["${var.apisix_global_subdomain}.${var.dns_zone}"]
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
  vault_helm_release_name  = "vault"
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
        "*.${local.vault_helm_release_name}-internal",
        "*.${local.vault_helm_release_name}-internal.${kubernetes_namespace.vault.metadata.0.name}",
        "*.${local.vault_helm_release_name}-internal.${kubernetes_namespace.vault.metadata.0.name}.svc",
        "*.${local.vault_helm_release_name}-internal.${kubernetes_namespace.vault.metadata.0.name}.svc.cluster.local",
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
  name             = local.vault_helm_release_name
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.28.0"
  namespace        = kubernetes_namespace.vault.metadata.0.name
  create_namespace = false

  values = [
    templatefile("./helm-values/vault-values-template.yaml", {
      cluster_issuer           = kubectl_manifest.clusterissuer_letsencrypt_prod.name,
      hostname                 = "${var.vault_subdomain}.${var.cluster_name}.${var.dns_zone}",
      ip                       = join(".", slice(split(".", data.kubernetes_service.ingress-nginx-controller.status[0].load_balancer[0].ingress[0].hostname), 0, 4)),
      vault_certificate_secret = local.vault_certificate_secret
      replicas                 = var.vault_replicas
      replicas_iterator        = range(var.vault_replicas)
      anti-affinity            = var.vault_anti-affinity
      release_name             = local.vault_helm_release_name
    })
  ]


  depends_on = [helm_release.cert-manager, helm_release.external-dns]

}

# Wait for vault container to be availible
resource "time_sleep" "wait_vault_before" {
  create_duration = "10s"
  depends_on      = [helm_release.vault]
}

data "kubernetes_resource" "vault-pods-before" {
  count = var.vault_replicas

  api_version = "v1"
  kind        = "Pod"

  metadata {
    name      = "${local.vault_helm_release_name}-${count.index}"
    namespace = kubernetes_namespace.vault.metadata.0.name
  }

  depends_on = [helm_release.vault, time_sleep.wait_vault_before]
}

data "external" "vault-init" {
  program = [
    "bash",
    "./ewc-vault-init/vault-init/vault-init.sh",
    var.kubeconfig_path,
    kubernetes_namespace.vault.metadata.0.name,
    join(" ", flatten([
      for pod in data.kubernetes_resource.vault-pods-before : [
        for condition in pod.object.status.conditions : condition.status
        if condition.type == "Ready"
      ]])
    ),
    var.vault_key_treshold,
    local.vault_helm_release_name
  ]

  depends_on = [helm_release.vault, time_sleep.wait_vault_before, data.kubernetes_resource.vault-pods-before]

}

# Wait for vault container to be ready
resource "time_sleep" "wait_vault_after" {
  create_duration = "10s"
  depends_on      = [helm_release.vault, time_sleep.wait_vault_before, data.kubernetes_resource.vault-pods-before, data.external.vault-init]
}

data "kubernetes_resource" "vault-pods-after" {
  count = var.vault_replicas

  api_version = "v1"
  kind        = "Pod"

  metadata {
    name      = "${local.vault_helm_release_name}-${count.index}"
    namespace = kubernetes_namespace.vault.metadata.0.name
  }

  depends_on = [helm_release.vault, time_sleep.wait_vault_before, data.kubernetes_resource.vault-pods-before, data.external.vault-init, time_sleep.wait_vault_after]
}
