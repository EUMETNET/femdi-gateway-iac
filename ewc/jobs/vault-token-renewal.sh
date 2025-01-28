#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
VAULT_ADDR=${VAULT_ADDR}
VAULT_ROLE=${VAULT_ROLE}

readarray -t TOKENS < /tmp/secret/tokens


# Check required variables
check_var "VAULT_ADDR" "$VAULT_ADDR"
check_var "VAULT_ROLE" "$VAULT_ROLE"
check_var "TOKENS" "$TOKENS"

error_occured=false

# Retrieve the provided service account token
SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Authenticate with Vault using the Kubernetes auth method to obtain a Vault token
export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login \
  role=$VAULT_ROLE \
  jwt=$SA_TOKEN)

for index in "${!TOKENS[@]}"; do
    echo "Renewing token index $index ..."
    vault token renew "${TOKENS[$index]}" > /dev/null || {
      echo "Error renewing $index"
      error_occurred=true
    }
done

if [ "$error_occurred" = true ]; then
  echo "One or more token renewals failed"
  exit 1
fi

echo "All Vault token renewals completed successfully"
