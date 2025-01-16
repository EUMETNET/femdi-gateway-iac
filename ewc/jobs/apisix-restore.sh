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
APISIX_HELM_RELEASE_NAME=${APISIX_HELM_RELEASE_NAME}
# Local variables
INITIAL_CLUSTER_TOKEN="etcd-cluster-k8s"
INITIAL_CLUSTER=""

# Check required variables
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "REPLICA_COUNT" "$REPLICA_COUNT"
check_var "NAMESPACE" "$NAMESPACE"
check_var "APISIX_HELM_RELEASE_NAME" "$APISIX_HELM_RELEASE_NAME"

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

# Construct the initial cluster configuration
for i in $(seq 0 $(($REPLICA_COUNT - 1))); do
  INITIAL_CLUSTER="${INITIAL_CLUSTER}${APISIX_HELM_RELEASE_NAME}-etcd-${i}=http://${APISIX_HELM_RELEASE_NAME}-etcd-${i}.${APISIX_HELM_RELEASE_NAME}-etcd-headless.${NAMESPACE}.svc.cluster.local:2380,"
done
INITIAL_CLUSTER=${INITIAL_CLUSTER%,}

# Restore the snapshot to each volume and form new logical cluster
echo "Restoring the snapshot to each etcd volume and forming new logical cluster..."
for i in $(seq 0 $(($REPLICA_COUNT - 1))); do
  volume="/etcd-volumes/data-${APISIX_HELM_RELEASE_NAME}-etcd-${i}"
  if [ -d "$volume" ]; then
    data_dir="$volume/data"  # Note: etcd statefulSet has env ETCD_DATA_DIR set to /bitnami/etcd/data hence just the /data
    rm -rf "$data_dir"
    mkdir -p "$data_dir"
    etcdutl snapshot restore /tmp/${DECOMPRESSED_SNAPSHOT_NAME} --data-dir "$data_dir" \
      --name "${APISIX_HELM_RELEASE_NAME}-etcd-${i}" \
      --initial-cluster "${INITIAL_CLUSTER}" \
      --initial-cluster-token "${INITIAL_CLUSTER_TOKEN}" \
      --initial-advertise-peer-urls "http://${APISIX_HELM_RELEASE_NAME}-etcd-${i}.${APISIX_HELM_RELEASE_NAME}-etcd-headless.${NAMESPACE}.svc.cluster.local:2380" \
      > /dev/null
    if [ $? -ne 0 ]; then
      echo "ERROR: Failed to restore snapshot to $data_dir"
      exit 1
    fi
  fi
done

# Clean up
rm /tmp/$DECOMPRESSED_SNAPSHOT_NAME

echo "APISIX etcd successfully restored from snapshot $DECOMPRESSED_SNAPSHOT_NAME"
