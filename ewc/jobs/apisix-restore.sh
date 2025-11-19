#!/bin/bash
set -e

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
SNAPSHOT_NAME=${SNAPSHOT_NAME:-"latest"}
REPLICA_COUNT=${REPLICA_COUNT}
NAMESPACE=${NAMESPACE}
# Local variables
STATEFULSET_NAME="etcd"
INITIAL_CLUSTER_TOKEN="etcd-apisix"
INITIAL_CLUSTER=""

# Check required variables
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "REPLICA_COUNT" "$REPLICA_COUNT"
check_var "NAMESPACE" "$NAMESPACE"

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

# Build cluster list
for i in $(seq 0 $(($REPLICA_COUNT - 1))); do
  INITIAL_CLUSTER="${INITIAL_CLUSTER}etcd-${i}=http://etcd-${i}.etcd.${NAMESPACE}.svc.cluster.local:2380,"
done
INITIAL_CLUSTER=${INITIAL_CLUSTER%,}

echo "Initial cluster: $INITIAL_CLUSTER"

echo "Restoring snapshot into PVCs..."

for i in $(seq 0 $(($REPLICA_COUNT - 1))); do
  data_dir="/etcd-volumes/etcd-data-etcd-${i}"
  if [ -d "$data_dir" ]; then
    rm -rf "${data_dir:?}/"*

    etcdutl snapshot restore "/tmp/${DECOMPRESSED_SNAPSHOT_NAME}" \
      --data-dir "$data_dir" \
      --name "etcd-${i}" \
      --initial-cluster "$INITIAL_CLUSTER" \
      --initial-cluster-token "$INITIAL_CLUSTER_TOKEN" \
      --initial-advertise-peer-urls "http://etcd-${i}.etcd.${NAMESPACE}.svc.cluster.local:2380"
      > /dev/null
    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to restore snapshot to $data_dir"
      exit 1
    fi
  fi
done

rm "/tmp/${DECOMPRESSED_SNAPSHOT_NAME}"
echo "Etcd cluster successfully restored."
