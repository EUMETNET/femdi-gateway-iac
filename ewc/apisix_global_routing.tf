# Manage global DNS record and ingress for it

# For clients we use a single DNS name and Route 53 handles the routing to correct cluster based on selected routing policy
# APISIX has service specific DNS names for each cluster (related services need access to cluster specific instances)
# The routing policy is set to latency based routing policy

locals {
  cluster_region_map = {
    "eumetsat" = "eu-central-1" # Frankfurt
    "ecmwf"    = "eu-south-1"   # Milan
  }
}

resource "aws_route53_health_check" "apisix_health" {
  fqdn              = "${local.apisix_subdomain}.${local.dns_zone}"
  type              = "HTTPS"
  port              = 443
  resource_path     = "/health"
  request_interval  = 30                                      # Default from UI
  failure_threshold = 3                                       # Default from UI
  regions           = ["eu-west-1", "us-east-1", "us-west-2"] # Three regions required
}

resource "aws_route53_record" "apisix" {
  for_each = nonsensitive(local.route53_hosted_zone_ids)
  zone_id  = each.value
  type     = "A"
  ttl      = 60
  name     = local.apisix_subdomain

  records = [module.ewc-vault-init.load_balancer_ip]

  set_identifier = var.cluster_name

  latency_routing_policy {
    region = local.cluster_region_map[var.cluster_name]
  }

  health_check_id = aws_route53_health_check.apisix_health.id
}

resource "kubectl_manifest" "apisix_global_ingress" {
  yaml_body = yamlencode({
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "name"      = "apisix-global"
      "namespace" = "${kubernetes_namespace.apisix.metadata.0.name}"
      "annotations" = {
        "cert-manager.io/cluster-issuer" = "${module.ewc-vault-init.cluster_issuer}"
        "app.kubernetes.io/instance"     = "apisix"
        "app.kubernetes.io/name"         = "apisix"
        "kubernetes.io/tls-acme"         = "true"
      }
    }
    "spec" = {
      "ingressClassName" = "nginx"
      "rules" = [
        {
          "host" = "${local.apisix_subdomain}.${local.dns_zone}"
          "http" = {
            "paths" = [
              {
                "path"     = "/"
                "pathType" = "ImplementationSpecific" # Same what is used in APISIX
                "backend" = {
                  "service" = {
                    "name" = "${local.apisix_helm_release_name}-gateway"
                    "port" = {
                      "number" = 80
                    }
                  }
                }
              }
            ]
          }
        }
      ]
      "tls" = [
        {
          "hosts"      = ["${local.apisix_subdomain}.${local.dns_zone}"]
          "secretName" = "${local.apisix_subdomain}.${local.dns_zone}-certificate"
        }
      ]
    }
  })
  depends_on = [helm_release.apisix]
}

resource "kubectl_manifest" "apisix-global-redirect" {
  yaml_body = yamlencode({
    "apiVersion" = "networking.k8s.io/v1"
    "kind"       = "Ingress"
    "metadata" = {
      "name"      = "apisix-permanent-redirect"
      "namespace" = "${kubernetes_namespace.apisix.metadata.0.name}"
      "annotations" = {
        "cert-manager.io/cluster-issuer"                 = "${module.ewc-vault-init.cluster_issuer}"
        "app.kubernetes.io/instance"                     = "apisix"
        "app.kubernetes.io/name"                         = "apisix"
        "kubernetes.io/tls-acme"                         = "true"
        "nginx.ingress.kubernetes.io/permanent-redirect" = "https://${local.apisix_subdomain}.${local.dns_zone}$request_uri"
      }
    }
    "spec" = {
      "rules" = [
        for domain in local.alternative_hosted_zone_names : {
          "host" = "${local.apisix_subdomain}.${domain}"
          "http" = {
            "paths" = [
              {
                "path"     = "/"
                "pathType" = "Prefix"
                # dummy backend, never actually used because redirect handles requests
                "backend" = {
                  "service" = {
                    "name" = "default-http-backend"
                    "port" = { "number" = 80 }
                  }
                }
              }
            ]
          }
        }
      ]
      "tls" = [
        {
          "hosts"      = [for name in local.alternative_hosted_zone_names : "${local.apisix_subdomain}.${name}"]
          "secretName" = "redirect-${local.apisix_subdomain}-certificate"
        }
      ]
    }
  })

  depends_on = [helm_release.apisix]
}
