#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
VAULT_ADDR=${VAULT_ADDR}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
VAULT_ROLE=${VAULT_ROLE}

# Check required variables
check_var "VAULT_ADDR" "$VAULT_ADDR"
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "VAULT_ROLE" "$VAULT_ROLE"

# Retrieve the provided service account token
SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)

# Authenticate with Vault using the Kubernetes auth method to obtain a Vault token
export VAULT_TOKEN=$(vault write -field=token auth/kubernetes/login \
  role=$VAULT_ROLE \
  jwt=$SA_TOKEN)

# Generate ISO 8601 compliant timestamp
TIMESTAMP_ISO_8601=$(generate_iso_8601_timestamp)

SNAPSHOT_NAME="snapshot-$TIMESTAMP_ISO_8601.snap"

# Take the snapshot
# https://developer.hashicorp.com/vault/tutorials/standard-procedures/sop-backup
echo "Taking the raft snapshot..."
vault operator raft snapshot save /tmp/$SNAPSHOT_NAME || { echo "ERROR: Failed to take raft snapshot"; exit 1; }

# Compress the snapshot
gzip /tmp/$SNAPSHOT_NAME

# Upload to S3
echo "Uploading the snapshot to S3..."
aws s3 cp /tmp/$SNAPSHOT_NAME.gz s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME}.gz --region "${AWS_REGION}" || { echo "ERROR: Failed to upload snapshot to S3"; exit 1; }

# Clean up
rm /tmp/$SNAPSHOT_NAME.gz

echo "Snapshot $SNAPSHOT_NAME has been successfully uploaded to S3"
