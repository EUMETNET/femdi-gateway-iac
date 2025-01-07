#!/bin/bash

set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
ETCD_ENDPOINT=${ETCD_ENDPOINT}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}

# Check required variables
check_var "ETCD_ENDPOINT" "$ETCD_ENDPOINT"
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"

# Generate ISO 8601 compliant timestamp
TIMESTAMP_ISO_8601=$(generate_iso_8601_timestamp)

SNAPSHOT_NAME="snapshot-$TIMESTAMP_ISO_8601.db"

# Take the etcd snapshot
echo "Taking the etcd snapshot..."
ETCDCTL_API=3 etcdctl --endpoints=${ETCD_ENDPOINT} snapshot save /tmp/$SNAPSHOT_NAME || { echo "ERROR: Failed to take etcd snapshot"; exit 1; }

# Compress the snapshot
gzip /tmp/$SNAPSHOT_NAME || { echo "ERROR: Failed to compress snapshot $SNAPSHOT_NAME"; exit 1; }

# Upload to S3
echo "Uploading the snapshot to S3..."
aws s3 cp /tmp/$SNAPSHOT_NAME.gz s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME}.gz --region "${AWS_REGION}" || { echo "ERROR: Failed to upload snapshot to S3"; exit 1; }

# Clean up
rm /tmp/$SNAPSHOT_NAME.gz

echo "Snapshot $SNAPSHOT_NAME has been successfully uploaded to S3"
