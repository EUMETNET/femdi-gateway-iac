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
│   ├── alertmanager_configs.tf
│   ├── apisix_global_routing.tf 
│   ├── dev-portal-init # Deploys dev-portal and its dependencies
│   │   ├── jobs.tf
│   │   ├── main.tf
│   │   ├── outuputs.tf
│   │   ├── terraform.tf
│   │   └── variables.tf
│   ├── ewc-vault-init # Deploys and Initializes Hashicorps Vaults
│   │   ├── main.tf
│   │   ├── outuputs.tf
│   │   ├── terraform.tf
│   │   ├── variables.tf
│   │   └── vault-init
│   │       └── vault-init.sh
│   ├── global-dns-records # Deploys global DNS records that are related to domain but not gateway itself
│   │   ├── main.tf
│   │   ├── variables.tf
│   ├── grafana-dashboards
│   │   ├── apisix-dashboard.json
│   │   ├── ingress-nginx-dashboard.json
│   │   ├── reguest-handling-performance-dashboard.json
│   │   └── vault-dashboard.json
│   ├── helm-values
│   │   ├── apisix-values-template.yaml
│   │   ├── dev-portal-values-template.yaml
│   │   ├── keycloak-values-template.yaml
│   │   └── vault-values-template.yaml
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
│   ├── jobs.tf
│   ├── keycloak-realm # Keycloak Realm default settings
│   │   └── realm-export.json
│   ├── main.tf
│   ├── monitoring.tf
│   ├── outuputs.tf
│   ├── README.md
│   ├── terraform.tf
│   └── variables.tf
└── scripts # Misc scripts
    └── test-users # Test user management scripts and files
        ├── generate_test_users.py
        ├── manage_users.sh
        ├── README.md
        └── requirements.txt
```
