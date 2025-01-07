#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
VAULT_ADDR=${VAULT_ADDR}
APISIX_SERVICE_TOKEN=${APISIX_SERVICE_TOKEN}
DEV_PORTAL_SERVICE_TOKEN=${DEV_PORTAL_SERVICE_TOKEN}

# Check required variables
check_var "VAULT_ADDR" "$VAULT_ADDR"
check_var "APISIX_SERVICE_TOKEN" "$APISIX_SERVICE_TOKEN"
check_var "DEV_PORTAL_SERVICE_TOKEN" "$DEV_PORTAL_SERVICE_TOKEN"

error_occured=false

# Retrieve the provided service account token
SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Authenticate with Vault using the Kubernetes auth method to obtain a Vault token
export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login \
  role=cron-jobs \
  jwt=$SA_TOKEN)

echo "Renewing APISIX service token..."
vault token renew $APISIX_SERVICE_TOKEN > /dev/null || {
  echo "Error renewing APISIX_SERVICE_TOKEN"
  error_occurred=true
}

echo "Renewing Dev Portal service token..."
vault token renew $DEV_PORTAL_SERVICE_TOKEN > /dev/null || {
  echo "Error renewing DEV_PORTAL_SERVICE_TOKEN"
  error_occurred=true
}

if [ "$error_occurred" = true ]; then
  echo "One or more token renewals failed"
  exit 1
fi

echo "All Vault token renewals completed successfully"
