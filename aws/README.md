# femdi-gateway-iac-aws

## Description

Terraform module for creating an Apisix-gateway running on an EKS-cluster in AWS.

## Instructions

In order to use the module, user needs to set a few variables before running `terraform apply`. Variables can be passed to the terraform command in multiple ways, choose what best suits your environment, some examples:

1. Set TF_VAR_variable environment variables
2. Pass variables in the command:
`terraform apply -var="certificateARN=arn:aws:acm:<aws-region>:<aws-account-id>:certificate/<certificate-id>`
3. Using terragrunt inputs block in `terragrunt.hcl` and run `terragrunt apply`:
```
inputs = {
  certificateARN = "arn:aws:acm:<aws-region>:<aws-account-id>:certificate/<certificate-id>"
}

```
## Included helm-charts

### aws-load-balancer-controller

AWS Load Balancer controller manages the AWS Network Load Balancer to satisfy Kubernetes service objects of type LoadBalancer with appropriate annotations.

### Apache APISIX for Kubernetes (AWS EKS)

Apache APISIX is a dynamic, real-time, high-performance API gateway.

## Included Kubernetes services

### AWS Network Loadbalancer

Kubernetes aws-load-balancer service annotations will create a Network Load Balancer in AWS which routes traffic from desired domains to the APISIX API Gateway running in EKS.

## EKS Add-ons installed

### aws-ebs-csi-driver

Allows PersistentVolumes to be dynamically provisioned using AWS EBS storage. 

Uses role `ebs_csi_irsa_role` and default gp2 storage class is replaced with gp3.

### amazon-cloudwatch-observability

Enables basic AWS CloudWatch logging.

## Instructions to deploy the module using environment variables:

Make sure you are authenticated as the user/role with enough permissions using `aws configure` and optionally `aws sts assume-role`, check your current credentials with `aws sts get-caller-identity`.

For AWS Network Load Balancer to work properly, user needs to add certificateARN:

`export TF_VAR_certificateARN=arn:aws:acm:<aws-region>:<aws-account-id>:certificate/<certificate-id>`

For APISIX API Gateway to work properly, user needs to add the environment variables for Admin- and Reader-API-keys and the IP-address whitelisting:

`export TF_VAR_apisixAdmin=<api-key-string>`

`export TF_VAR_apisixReader=<api-key-string>`

`export TF_VAR_apisixIpList={0.0.0.0/0}`

Run `terraform init`

Run `terraform apply`
