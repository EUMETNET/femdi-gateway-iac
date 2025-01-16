#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SNAPSHOT_NAME=${SNAPSHOT_NAME:-"latest"}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
NAMESPACE=${NAMESPACE}
REPLICA_COUNT=${REPLICA_COUNT}
KEYCLOAK_HELM_RELEASE_NAME=${KEYCLOAK_HELM_RELEASE_NAME}

# Check required variables
check_var "POSTGRES_HOST" "$POSTGRES_HOST"
check_var "POSTGRES_DB" "$POSTGRES_DB"
check_var "POSTGRES_USER" "$POSTGRES_USER"
check_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "NAMESPACE" "$NAMESPACE"
check_var "REPLICA_COUNT" "$REPLICA_COUNT"
check_var "KEYCLOAK_HELM_RELEASE_NAME" "$KEYCLOAK_HELM_RELEASE_NAME"

# Ensure the Keycloak StatefulSet is available
echo "Ensuring the Keycloak StatefulSet is available..."
if ! kubectl get statefulset "$KEYCLOAK_HELM_RELEASE_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo "ERROR: StatefulSet $KEYCLOAK_HELM_RELEASE_NAME not found in namespace $NAMESPACE"
  exit 1
fi

# Ensure PostgreSQL is accessible
echo "Ensuring PostgreSQL is accessible..."
if ! PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres -c '\q' > /dev/null 2>&1; then
  echo "ERROR: Unable to connect to PostgreSQL at $POSTGRES_HOST"
  exit 1
fi

# Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  echo "Finding the latest snapshot from S3..."
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION) || { echo "ERROR: Failed to download snapshot $SNAPSHOT_NAME from S3"; exit 1; }
fi

# Download the snapshot from S3
echo "Downloading the snapshot "$SNAPSHOT_NAME" from S3..."
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}" || { echo "ERROR: Failed to download snapshot from S3"; exit 1; }

# Decompress the snapshot
gzip -d /tmp/${SNAPSHOT_NAME} || { echo "ERROR: Failed to decompress snapshot $SNAPSHOT_NAME"; exit 1; }

# Create a new variable for the decompressed snapshot name
DECOMPRESSED_SNAPSHOT_NAME="${SNAPSHOT_NAME%.gz}"

# Scale the Keycloak StatefulSet down to prevent writes
echo "Scaling down the Keycloak StatefulSet to prevent writes to PostgreSQL..."
kubectl scale statefulset "$KEYCLOAK_HELM_RELEASE_NAME" --replicas=0 -n "$NAMESPACE" || { echo "ERROR: Failed to scale down Keycloak StatefulSet"; exit 1; }

# Wait for the StatefulSet to scale down
echo "Waiting for the Keycloak StatefulSet to scale down..."
kubectl wait --for=delete pod -l app.kubernetes.io/instance=${KEYCLOAK_HELM_RELEASE_NAME},app.kubernetes.io/name=keycloak -n "$NAMESPACE" --timeout=300s || { echo "ERROR: Timeout reached when waiting for Keycloak StatefulSet to scale down "; exit 1; }
echo "Keycloak StatefulSet scaled down successfully"

# Restore the PostgreSQL database from the snapshot
# -c for clean state before restore
echo "Restoring the PostgreSQL database from the snapshot..."
PGPASSWORD=$POSTGRES_PASSWORD pg_restore -h $POSTGRES_HOST -U $POSTGRES_USER -d postgres /tmp/$DECOMPRESSED_SNAPSHOT_NAME -C -c --if-exists > /dev/null || { echo "ERROR: Failed to restore PostgreSQL database from snapshot"; exit 1; }

# Scale up the Keycloak StatefulSet back to its original replica count
echo "Scaling up the Keycloak StatefulSet back to its original replica count..."
kubectl scale statefulset "$KEYCLOAK_HELM_RELEASE_NAME" --replicas=${REPLICA_COUNT} -n "$NAMESPACE" || { echo "ERROR: Failed to scale up Keycloak StatefulSet"; exit 1; }

# Wait for the StatefulSet to scale up
echo "Waiting for the Keycloak StatefulSet to scale up..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=${KEYCLOAK_HELM_RELEASE_NAME},app.kubernetes.io/name=keycloak -n "$NAMESPACE" --timeout=300s || { echo "ERROR: Timeout reached when waiting for Keycloak StatefulSet to scale up"; exit 1; }
echo "Keycloak StatefulSet scaled up successfully"

# Clean up
rm /tmp/$DECOMPRESSED_SNAPSHOT_NAME

echo "Keycloak PostgreSQL database successfully restored from snapshot $DECOMPRESSED_SNAPSHOT_NAME"
