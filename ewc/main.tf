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
# Install ingress nginx under System project
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
  name = "ingress-nginx "
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart = "ingress-nginx "
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
