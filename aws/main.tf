provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
      command     = "aws"
    }
  }
}

locals {
  cluster_name = "terra-apisix"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "terra-apisix-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    
    default = {      
      name = "${var.cluster_name}-ng1"
      instance_types = ["m5.large"]
      block_device_mappings = {
        
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 80
            volume_type = "gp3"
            iops = 3000
            throughput = 125
          }
        }
      }

      min_size     = 1
      max_size     = 3
      desired_size = 2

      # Policies needed for AWS Cloudwatch Observability add-on 
      iam_role_additional_policies = {
        CloudWatchAgentServerPolicy = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
        AWSXrayWriteOnlyAccess = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
      }
    }
  }

  # Add-ons
  cluster_addons = {
    amazon-cloudwatch-observability = {
      most_recent = true
    }
  }

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

}

data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "4.7.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

resource "aws_eks_addon" "ebs-csi" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = "v1.28.0-eksbuild.1"
  service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
  tags = {
    "eks_addon" = "ebs-csi"
    "terraform" = "true"
  }
}

resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }

  force = true

  depends_on = [module.eks]
}

resource "kubernetes_storage_class" "ebs_csi_aws_storage_class" {
  metadata {
    name = "ebs-csi-aws-gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Retain"
  allow_volume_expansion = true
  volume_binding_mode    = "Immediate"
  parameters = {
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

################################################################################
# Load Balancer Role
################################################################################

module "lb_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "${var.env_name}_eks_lb"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

################################################################################
# Aws Load balancer Controller Service Account
################################################################################

resource "kubernetes_service_account" "service-account" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn"               = module.lb_role.iam_role_arn
      "eks.amazonaws.com/sts-regional-endpoints" = "true"
    }
  }
}

################################################################################
# Install Load Balancer Controler With Helm
################################################################################

resource "helm_release" "lb" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  depends_on = [
    kubernetes_service_account.service-account
  ]

  set {
    name  = "region"
    value = var.main-region
  }

  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.${var.main-region}.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "clusterName"
    value = var.cluster_name
  }
}

################################################################################
# Install Apisix With Helm
################################################################################

resource "helm_release" "apisix" {
  name       = "apisix-tf"
  repository = "https://charts.apiseven.com"
  chart      = "apisix"
  namespace  = "apisix-tf"
  create_namespace = true

  set {
    name  = "etcd.persistence.storageClass"
    value = "ebs-csi-aws-gp3"
  }

  set {
    name  = "apisix.admin.credentials.admin"
    value = var.apisixAdmin
  }

  set {
    name  = "apisix.admin.credentials.viewer"
    value = var.apisixReader
  }

  set {
    name  = "apisix.admin.allow.ipList"
    value = var.apisixIpList
  }

  depends_on = [module.eks]

}

###########################
# AWS Network Loadbalancer
###########################

resource "kubernetes_service" "aws-nlb" {
  metadata {
    name = "nlb-apisix-tf-service"
    namespace = "apisix-tf"
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "external",
      "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing",
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip",
      "service.beta.kubernetes.io/aws-load-balancer-ssl-cert" = var.certificateARN,
      "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes" = "preserve_client_ip.enabled=true"
      }
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "apisix"
    }
    
    port {
      name        = "gateway"
      port        = 443
      target_port = 9080
    }

    port {
      name        = "admin"
      port        = 9180
      target_port = 9180
    }

    type = "LoadBalancer"
  }
}