#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
SNAPSHOT_NAME=${SNAPSHOT_NAME:-"latest"}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
NAMESPACE=${NAMESPACE}
KEY_THRESHOLD=${KEY_THRESHOLD}
VAULT_TOKEN=${VAULT_TOKEN}
UNSEAL_KEYS=${UNSEAL_KEYS}

# Check required variables
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "NAMESPACE" "$NAMESPACE"
check_var "KEY_THRESHOLD" "$KEY_THRESHOLD"
check_var "VAULT_TOKEN" "$VAULT_TOKEN"
check_var "UNSEAL_KEYS" "$UNSEAL_KEYS"


# Validate and convert KEY_THRESHOLD to an integer
if ! [[ "$KEY_THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "ERROR: KEY_THRESHOLD must be a valid integer."
  exit 1
fi
KEY_THRESHOLD=$(printf "%d" "$KEY_THRESHOLD")

# Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION)
fi

# Download the snapshot from S3
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}" || { echo "ERROR: Failed to download snapshot $SNAPSHOT_NAME from S3"; exit 1; }

# Get the Vault pods
echo "Getting the available Vault pods..."
VAULT_PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}')
if [ -z "$VAULT_PODS" ]; then
  echo "ERROR: No available Vault pods found"
  exit 1
fi

# Select the first Vault pod for initialization and restore
VAULT_POD=$(echo $VAULT_PODS | awk '{print $1}')
echo "Using first found Vault pod: '$VAULT_POD' to perform the restore."

# Check that the Vault cluster is initialized
echo "Verifying that the Vault cluster is initialized..."
kubectl -n "$NAMESPACE" exec "${VAULT_POD}" -- vault status -format=json > /tmp/init.json

if [ "$(grep -o '\"initialized\": *[^,]*' /tmp/init.json | awk '{print $2}')" != "true" ]; then
  echo "ERROR: Vault cluster is not initialized."
  exit 1
fi

# Copy the snapshot to the Vault pod
echo "Copying snapshot to the Vault pod using tar..."
tar cf - -C /tmp ${SNAPSHOT_NAME} | kubectl exec -i -n "$NAMESPACE" "$VAULT_POD" -- tar xf - -C /tmp/
if [ $? -ne 0 ]; then
  echo "ERROR: Failed to copy snapshot to the Vault pod"
  exit 1
fi

# Restore the Vault cluster from snapshot
echo "Restoring the Vault cluster from snapshot..."
kubectl -n "$NAMESPACE" exec "${VAULT_POD}" -- sh -c \
  "VAULT_TOKEN=$VAULT_TOKEN vault operator raft snapshot restore -force /tmp/$SNAPSHOT_NAME &&
  rm /tmp/$SNAPSHOT_NAME" || { echo "ERROR: Failed to restore the Vault cluster from snapshot"; exit 1; }

# Unseal the Vault cluster
echo "Unsealing the Vault cluster..."
IFS=',' read -r -a keys <<< "$UNSEAL_KEYS"
for pod in $VAULT_PODS; do
  for (( i=0; i<$KEY_THRESHOLD; i++ )); do
    kubectl -n "$NAMESPACE" exec "$pod" -- vault operator unseal "${keys[$i]}" || { echo "ERROR: Failed to unseal pod $pod"; exit 1; }
  done
done

# Verifying that the Vault StatefulSet is ready
echo "Verifying that the Vault pods are joining the cluster..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n "$NAMESPACE" --timeout=300s || { echo "ERROR: Timeout reached when waiting for Vault StatefulSet to be ready"; exit 1; }


# Clean up
rm /tmp/$SNAPSHOT_NAME
rm /tmp/init.json

echo "Vault cluster successfully restored from snapshot $SNAPSHOT_NAME"
