#!/bin/bash

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
SNAPSHOT_NAME=${SNAPSHOT_NAME}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
NAMESPACE=${NAMESPACE}
KEY_TRESHOLD=${KEY_TRESHOLD}
UNSEAL_KEYS=${UNSEAL_KEYS}
VAULT_NAME=${VAULT_NAME:-NAMESPACE}

# Check required variables
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "NAMESPACE" "$NAMESPACE"
check_var "KEY_TRESHOLD" "$KEY_TRESHOLD"
check_var "UNSEAL_KEYS" "$UNSEAL_KEYS"


# Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION)
fi

# Download the snapshot from S3
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}"

# Reinitialize the Vault cluster
kubectl -n "$NAMESPACE" exec "${VAULT_NAME}-0" -- vault operator init -t $KEY_TRESHOLD -format=json > /tmp/init.json

# Restore from snapshot
# Vault will propagate the snapshot data to the other pods in the cluster once they are unsealed.
kubectl cp /tmp/${SNAPSHOT_NAME} "${NAMESPACE}/${VAULT_NAME}-0:/tmp/${SNAPSHOT_NAME}"
kubectl -n "$NAMESPACE" exec "${VAULT_NAME}-0" -- sh -c \
  "vault operator raft snapshot restore -force /tmp/$SNAPSHOT_NAME &&
  rm /tmp/$SNAPSHOT_NAME"

# Get the Vault pods and unseal them
$VAULT_PODS=$(kubectl -n "$NAMESPACE" get pods -l "app.kubernetes.io/name=${VAULT_NAME}" -o jsonpath='{.items[*].metadata.name}')

IFS=',' read -r -a keys <<< "$UNSEAL_KEYS"
for pod in $VAULT_PODS; do
  for (( i=0; i<$KEY_TRESHOLD; i++ )); do
    kubectl -n "$NAMESPACE" exec "$pod" -- vault operator unseal "${keys[$i]}"
  done
done

# Verify that each Vault pod has joined the Raft cluster
echo "Verifying that each Vault pod has joined the Raft cluster..."
START_TIME=$(date +%s)
for pod in $VAULT_PODS; do
  while true; do
    READY=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$READY" == "True" ]; then
      echo "Vault pod $pod has joined the Raft cluster"
      break
    fi
    CURRENT_TIME=$(date +%s)
    ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
    if [ "$ELAPSED_TIME" -ge "$TIMEOUT" ]; then
      echo "Error: Timeout waiting for all the Vault pods to join the Raft cluster"
      exit 1
    fi
    echo "Waiting for Vault pod $pod to join the Raft cluster..."
    sleep 5
  done
done

echo "Vault cluster restored successfully from snapshot $SNAPSHOT_NAME"

# Clean up
rm /tmp/$SNAPSHOT_NAME
rm /tmp/init.json
