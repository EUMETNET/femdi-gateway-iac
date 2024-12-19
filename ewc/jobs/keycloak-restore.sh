#!/bin/bash

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SNAPSHOT_NAME=${SNAPSHOT_NAME}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
NAMESPACE=${NAMESPACE}
KEYCLOAK_NAME=${KEYCLOAK_NAME:-NAMESPACE}

# Check required variables
check_var "POSTGRES_HOST" "$POSTGRES_HOST"
check_var "POSTGRES_DB" "$POSTGRES_DB"
check_var "POSTGRES_USER" "$POSTGRES_USER"
check_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "NAMESPACE" "$NAMESPACE"

## Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION)
fi

# Download the snapshot from S3
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}"

# Perform the cold restore

# Scale the Keycloak StatefulSet down to 0
kubectl scale statefulset "$KEYCLOAK_NAME" --replicas=0 -n "$NAMESPACE"

# Wait for the StatefulSet to scale down
kubectl wait --for=delete pod -l "app.kubernetes.io/name=${KEYCLOAK_NAME}" -n "$NAMESPACE" --timeout=300s

# Restore the PostgreSQL database from the snapshot
PGPASSWORD=$POSTGRES_PASSWORD pg_restore -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DB -v /tmp/$SNAPSHOT_NAME

# Scale up the Keycloak StatefulSet back to its original replica count
kubectl scale statefulset keycloak --replicas=1 -n "$NAMESPACE"

# Wait for the StatefulSet to scale up
kubectl wait --for=condition=ready pod -l "app.kubernetes.io/name=${KEYCLOAK_NAME}" -n "$NAMESPACE" --timeout=300s

# Clean up
rm /tmp/$SNAPSHOT_NAME

echo "Keycloak PostgreSQL database restored successfully from snapshot $SNAPSHOT_NAME"
