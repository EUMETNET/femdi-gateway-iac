# EURODEO Meteogate Infrastructure

## Dependencies
The `EWC` module requires `Bash` and `jq`

```bash
femdi-gateway-iac
├── apisix # Contains files for configuring Apisix on all environments
│   ├── error_pages
│   │   ├── apisix_error_403.html
│   │   └── apisix_error_429.html
│   └── error_values
│       ├── httpSrv
│       └── httpStart
├── aws # Deploy Apisix on AWS
│   ├── main.tf
│   ├── outputs.tf
│   ├── README.md
│   ├── terraform.tf
│   └── variables.tf
├── ewc # Deploy Apisix on EWC Rancher Cluster
│   ├── dev-portal-init # Deploys dev-portal and its dependencies
│   │   ├── jobs.tf
│   │   ├── locals.tf
│   │   ├── main.tf
│   │   ├── outuputs.tf
│   │   ├── ssm.tf
│   │   ├── terraform.tf
│   │   └── variables.tf
│   ├── ewc-vault-init # Deploys and Initializes Hashicorps Vaults
│   │   ├── locals.tf
│   │   ├── main.tf
│   │   ├── outuputs.tf
│   │   ├── ssm.tf
│   │   ├── terraform.tf
│   │   ├── variables.tf
│   │   └── vault-init
│   │       └── vault-init.sh
│   ├── geoweb # Deploys and Initializes Geoweb related apps
│   │   ├── main.tf
│   │   ├── terraform.tf
│   │   ├── variables.tf
│   ├── grafana-dashboards
│   │   ├── apisix-dashboard.json
│   │   ├── ingress-nginx-dashboard.json
│   │   ├── reguest-handling-performance-dashboard.json
│   │   └── vault-dashboard.json
│   ├── jobs # Kubernetes jobs as bash script
│   │   ├── apisix-restore.sh
│   │   ├── apisix-snapshot.sh
│   │   ├── common-functions.sh
│   │   ├── Dockerfile
│   │   ├── keycloak-restore.sh
│   │   ├── keycloak-snapshot.sh
│   │   ├── vault-restore.sh
│   │   ├── vault-snapshot.sh
│   │   └── vault-token-renewal.sh
│   ├── keycloak-realm # Keycloak Realm default settings
│   │   └── realm-export.json
│   ├── templates
│   │   ├── helm-values
│   │   │    ├── apisix-values-template.yaml
│   │   │    ├── dev-portal-values-template.yaml
│   │   │    ├── keycloak-values-template.yaml
│   │   │    └── vault-values-template.yaml
│   │   └── service-redirect-ingress.yaml
│   ├── .terraform.lock.hcl
│   ├── alertmanager_configs.tf
│   ├── apisix_global_routing.tf
│   ├── backend.tf
│   ├── jobss.tf
│   ├── locals.tf
│   ├── main.tf
│   ├── monitoring.tf
│   ├── outuputs.tf
│   ├── README.md
│   ├── locals.tf
│   ├── terraform.tf
│   └── variables.tf
├── global # Contains global AWS account related configurations
│   ├── backend.tf
│   ├── iam.tf
│   ├── output.tf
│   ├── provider.tf
│   ├── route53.tf
│   ├── s3.tf
│   ├── ssm.tf
│   └── variables.tf
└── scripts # Misc scripts
```
