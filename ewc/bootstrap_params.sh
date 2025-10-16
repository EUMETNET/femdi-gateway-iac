#!/bin/bash
set -e

# Edit these lists to match your secure and stringlist keys
SECURE_KEYS=("vault/root_token" "vault/unseal_keys" "keycloak/github_idp_client_secret" "keycloak/google_idp_client_secret")
STRINGLIST_KEYS=("apisix/admin_api_ip_list" "apisix/ingress_nginx_private_subnets")

# Parameter file: first argument or default
PARAM_FILE="${1:-.env.params}"

# Extract cluster_name
CLUSTER_NAME=""
while IFS='=' read -r key value; do
  [[ "$key" == "cluster_name" ]] && CLUSTER_NAME="$value"
done < "$PARAM_FILE"

if [[ -z "$CLUSTER_NAME" ]]; then
  echo "cluster_name must be set in $PARAM_FILE"
  exit 1
fi

echo "Bootstrapping cluster '$CLUSTER_NAME' parameters to AWS SSM Parameter Store"

# put parameters to SSM
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  [[ -z "$key" || "$key" == "cluster_name" || "$key" =~ ^# ]] && continue

  # Remove possible surrounding quotes
  value="${value%\"}"
  value="${value#\"}"

  # Determine parameter type
  if [[ " ${SECURE_KEYS[@]} " =~ " $key " ]]; then
    TYPE="SecureString"
  elif [[ " ${STRINGLIST_KEYS[@]} " =~ " $key " ]]; then
    TYPE="StringList"
    # Remove brackets and spaces for stringlist, if present
    value="${value#[}"
    value="${value%]}"
    value="${value// /}"
  else
    TYPE="String"
  fi

  PARAM_NAME="/${CLUSTER_NAME}/${key}"

  echo "Put $PARAM_NAME as $TYPE"
  aws ssm put-parameter --name "$PARAM_NAME" --value "$value" --type "$TYPE" --overwrite --region eu-north-1 --no-cli-pager
done < "$PARAM_FILE"

echo "Bootstrap completed."
