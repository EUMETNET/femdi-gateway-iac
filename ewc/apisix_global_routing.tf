# Manage global DNS record and ingress for it

# For clients we use a single DNS name and Route 53 handles the routing to correct cluster based on selected routing policy
# APISIX has service specific DNS names for each cluster (related services need access to cluster specific instances)
# The routing policy is set to latency based routing policy

locals {
  apisix_global_dns_name = "${var.apisix_global_subdomain}.${var.new_dns_zone}"
  cluster_region_map = {
    "eumetsat" = "eu-central-1" # Frankfurt
    "ecmwf"    = "eu-south-1"   # Milan
  }
}

resource "aws_route53_health_check" "apisix_health" {
  fqdn              = local.apisix_global_dns_name
  type              = "HTTPS"
  port              = 443
  resource_path     = "/health"
  request_interval  = 30                                      # Default from UI
  failure_threshold = 3                                       # Default from UI
  regions           = ["eu-west-1", "us-east-1", "us-west-2"] # Three regions required
  disabled          = true                                    # enable once nameservers pointed to hosted zone 
}

resource "aws_route53_record" "apisix" {
  zone_id = var.new_route53_zone_id_filter
  type    = "A"
  ttl     = 60
  name    = var.apisix_global_subdomain

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
        "kubernetes.io/ingress.class"    = "nginx"
        "kubernetes.io/tls-acme"         = "true"
      }
    }
    "spec" = {
      "rules" = [
        {
          "host" = "${local.apisix_global_dns_name}"
          "http" = {
            "paths" = [
              {
                "path"     = "/"
                "pathType" = "Prefix"
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
    }
    "tls" = [
      {
        "hosts"      = ["${local.apisix_global_dns_name}"]
        "secretName" = "${local.apisix_global_dns_name}-certificate"
      }
    ]
  })
  depends_on = [helm_release.apisix]
}
