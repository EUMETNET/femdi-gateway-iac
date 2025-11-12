# Global

## Description

Terraform project for managing global account level resources including Route53, S3 backup bucket and iam users (keys) for accessing backup bucket and route53.

## Variables

All the required variables are fetched from AWS SSM Parameter Store. The resources that are created here and needed as variables in cluster projects are stored in Parameter Store as well. Clusters can then reference those values from SSM directly.

## Instructions

Project needs AWS profile called `fmi_meteogate` in AWS configs to be able to perform the operations. 

One way to configure the profile is to use aws sso:
```bash
aws configure sso
```

Then retrieve short-term credentials using:
```bash
aws sso login --profile fmi_meteogate
```

Initialize the Terraform project:
```bash
terraform init
```

Plan the desired changes:
```bash
terraform plan
```

Apply the desired changes:
```bash
terraform apply
```
