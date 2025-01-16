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
  echo "ERROR: KEY_THRESHOLD must be a valid integer. Provided value: $KEY_THRESHOLD"
  exit 1
fi
KEY_THRESHOLD=$(printf "%d" "$KEY_THRESHOLD")

# Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  echo "Finding the latest snapshot from S3..."
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION) || { echo "ERROR: Failed to download snapshot $SNAPSHOT_NAME from S3"; exit 1; }
fi

# Download the snapshot from S3
echo "Downloading the snapshot "$SNAPSHOT_NAME" from S3..."
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}" || { echo "ERROR: Failed to download snapshot $SNAPSHOT_NAME from S3"; exit 1; }

# Decompress the snapshot
gzip -d /tmp/${SNAPSHOT_NAME} || { echo "ERROR: Failed to decompress snapshot $SNAPSHOT_NAME"; exit 1; }

# Create a new variable for the decompressed snapshot name
DECOMPRESSED_SNAPSHOT_NAME="${SNAPSHOT_NAME%.gz}"

# Get the Vault pods
echo "Getting the available Vault pods..."
VAULT_PODS=$(kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}')
if [ -z "$VAULT_PODS" ]; then
  echo "ERROR: No available Vault pods found"
  exit 1
fi

# Check that the Vault cluster is initialized
echo "Verifying that the pods in Vault cluster are in initialized state..."
for pod in $VAULT_PODS; do
  initialized=$(kubectl -n "$NAMESPACE" exec "$pod" -- sh -c "vault status -format=json" | grep -o '"initialized":[^,]*' | awk -F: '{print $2}' | tr -d ' ')
  if [ "$initialized" != "true" ]; then
    echo "ERROR: Vault pod $pod is not initialized. All the Vault pods needs to be initialized before restoring from snapshot."
    exit 1
  fi
done

# Select the first Vault pod for restore
VAULT_POD=$(echo $VAULT_PODS | awk '{print $1}')
echo "Using first found Vault pod: '$VAULT_POD' to perform the restore."

# Copy the snapshot to the Vault pod
# Had issues with kubectl cp, so using tar instead
echo "Copying snapshot to the Vault pod using tar..."
tar cf - -C /tmp ${DECOMPRESSED_SNAPSHOT_NAME} | kubectl exec -i -n "$NAMESPACE" "$VAULT_POD" -- tar xf - -C /tmp/ || { echo "ERROR: Failed to copy snapshot to the Vault pod"; exit 1; }

# Restore the Vault cluster from snapshot
echo "Restoring the Vault cluster from snapshot..."
kubectl -n "$NAMESPACE" exec "${VAULT_POD}" -- sh -c \
  "VAULT_TOKEN=$VAULT_TOKEN vault operator raft snapshot restore -force /tmp/$DECOMPRESSED_SNAPSHOT_NAME &&
  rm /tmp/$DECOMPRESSED_SNAPSHOT_NAME" || { echo "ERROR: Failed to restore the Vault cluster from snapshot"; exit 1; }

# Unseal the Vault cluster
echo "Unsealing the Vault cluster..."
IFS=',' read -r -a keys <<< "$UNSEAL_KEYS"
for pod in $VAULT_PODS; do
  for (( i=0; i<$KEY_THRESHOLD; i++ )); do
    kubectl -n "$NAMESPACE" exec "$pod" -- vault operator unseal "${keys[$i]}" > /dev/null || { echo "ERROR: Failed to unseal pod $pod"; exit 1; }
  done
done

# Verifying that the Vault StatefulSet is ready
echo "Verifying that the Vault pods are joining the cluster..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n "$NAMESPACE" --timeout=300s || { echo "ERROR: Timeout reached when waiting for Vault StatefulSet to be ready"; exit 1; }
echo "Vault cluster is ready"

# Clean up
rm /tmp/$DECOMPRESSED_SNAPSHOT_NAME

echo "Vault cluster successfully restored from snapshot $DECOMPRESSED_SNAPSHOT_NAME"
