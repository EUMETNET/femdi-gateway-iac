provider "helm" {
  kubernetes = {
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

  set = [
    {
      name  = "image.repository"
      value = "bitnamilegacy/external-dns"
    },
    {
      name  = "image.tag"
      value = "0.13.5-debian-11-r79"
    },
    {
      name  = "policy"
      value = "upsert-only"
    },
    {
      name  = "controller.ingressClassResource.default"
      value = true
    },
    {
      name  = "aws.credentials.accessKey"
      value = var.route53_access_key
    },
    {
      name  = "aws.credentials.secretKey"
      value = var.route53_secret_key
    }
  ]

  set_list = [
    {
      name  = "zoneIdFilters"
      value = var.route53_hosted_zone_ids
    },
    # Global APISIX subdomain handled separately
    {
      name  = "excludeDomains"
      value = [for name in var.hosted_zone_names : "${var.apisix_subdomain}.${name}"]
    }
  ]
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

#https://cert-manager.io/v1.19-docs/installation/helm/#option-1-installing-crds-with-kubectl
data "http" "cert_manager_crds" {
  url = "https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.crds.yaml"
}

data "kubectl_file_documents" "cert_manager_crds" {
  content = data.http.cert_manager_crds.response_body
}

resource "kubectl_manifest" "cert_manager_crds" {
  for_each   = data.kubectl_file_documents.cert_manager_crds.manifests
  yaml_body  = each.value
  depends_on = [kubernetes_namespace.cert-manager]
}

resource "helm_release" "cert-manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io/"
  chart            = "cert-manager"
  version          = "1.19.1"
  namespace        = kubernetes_namespace.cert-manager.metadata.0.name
  create_namespace = false

  set = [
    {
      name  = "installCRDs"
      value = false
    },
  ]
  depends_on = [kubectl_manifest.cert_manager_crds]
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
        "email" = local.cert_manager_email
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
              "dnsZones" = var.hosted_zone_names
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
    templatefile("./templates/helm-values/vault-values-template.yaml", {
      cluster_issuer           = kubectl_manifest.clusterissuer_letsencrypt_prod.name,
      hostname                 = "${var.vault_subdomain}.${var.cluster_name}.${var.dns_zone}",
      ip                       = join(".", slice(split(".", data.kubernetes_service.ingress-nginx-controller.status[0].load_balancer[0].ingress[0].hostname), 0, 4)),
      vault_certificate_secret = local.vault_certificate_secret
      replicas                 = local.vault_replica_count
      replicas_iterator        = range(local.vault_replica_count)
      anti-affinity            = local.vault_anti_affinity
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
  count = local.vault_replica_count

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
  count = local.vault_replica_count

  api_version = "v1"
  kind        = "Pod"

  metadata {
    name      = "${local.vault_helm_release_name}-${count.index}"
    namespace = kubernetes_namespace.vault.metadata.0.name
  }

  depends_on = [helm_release.vault, time_sleep.wait_vault_before, data.kubernetes_resource.vault-pods-before, data.external.vault-init, time_sleep.wait_vault_after]
}

# Create ingress to redirect alternative domains to main domain
# About issue of permanent redirects with $redirect_uri 
# https://github.com/kubernetes/ingress-nginx/issues/11175
resource "kubectl_manifest" "cluster-vault-redirect" {
  yaml_body = templatefile(
    "./templates/service-redirect-ingress.yaml",
    {
      namespace             = kubernetes_namespace.vault.metadata.0.name
      cluster_issuer        = kubectl_manifest.clusterissuer_letsencrypt_prod.name,
      external_dns_hostname = join(",", [for name in local.alternative_hosted_zone_names : "${var.vault_subdomain}.${var.cluster_name}.${name}"])
      target_address        = join(".", slice(split(".", data.kubernetes_service.ingress-nginx-controller.status[0].load_balancer[0].ingress[0].hostname), 0, 4)),
      permanent_redirect    = "https://${var.vault_subdomain}.${var.cluster_name}.${var.dns_zone}"
      redirect_domains      = [for name in local.alternative_hosted_zone_names : "${var.vault_subdomain}.${var.cluster_name}.${name}"]
      subdomain             = var.vault_subdomain
      cluster_name          = var.cluster_name
    }
  )
  depends_on = [helm_release.vault]
}
