# Global

## Description

Terraform project for managing global account level resources.

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
terraform plan -var-file=<your_file>.tfvars
```

Apply the desired changes:
```bash
terraform apply -var-file=<your_file>.tfvars
```
