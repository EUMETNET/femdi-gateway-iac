#!/bin/bash

# Source common functions
source /usr/local/bin/common-functions.sh

# Variables
ETCD_ENDPOINT=${ETCD_ENDPOINT}
S3_BUCKET_BASE_PATH=${S3_BUCKET_BASE_PATH}
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_REGION=${AWS_REGION:-"eu-north-1"}
NAMESPACE=${NAMESPACE}
REPLICA_COUNT=${REPLICA_COUNT}

ETCD_INITIAL_CLUSTER=""

# Check required variables
check_var "ETCD_ENDPOINT" "$ETCD_ENDPOINT"
check_var "S3_BUCKET_BASE_PATH" "$S3_BUCKET_BASE_PATH"
check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "NAMESPACE" "$NAMESPACE"

# NOT WORKING YET!!!
# JUST SOME "SCRATCH" PAPER NOTES AND IDEAS FOR NOW

# Find the latest snapshot if no specific snapshot is provided
if [ "$SNAPSHOT_NAME" == "latest" ]; then
  SNAPSHOT_NAME=$(find_latest_file_in_s3_bucket $S3_BUCKET_BASE_PATH $AWS_REGION)
fi

# Download the snapshot from S3
aws s3 cp s3://${S3_BUCKET_BASE_PATH}${SNAPSHOT_NAME} /tmp/${SNAPSHOT_NAME} --region "${AWS_REGION}"

if [ $? -ne 0 ]; then
  echo "Error: Failed to download snapshot from S3"
  exit 1
fi

STATEFULSET_JSON=$(kubectl get statefulset ${NAMESPACE}-etcd -n ${NAMESPACE} -o json)

# Extract needed values from the statefulset
ETCD_INITIAL_CLUSTER_TOKEN=$(echo $STATEFULSET_JSON | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "ETCD_INITIAL_CLUSTER_TOKEN") | .value')

ETCD_INITIAL_CLUSTER=$(echo $STATEFULSET_JSON | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "ETCD_INITIAL_CLUSTER") | .value')

ETCD_INITIAL_ADVERTISE_PEER_URLS_TEMPLATE=$(echo $STATEFULSET_JSON | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "ETCD_INITIAL_ADVERTISE_PEER_URLS") | .value')

ETCD_DATA_DIR=$(echo $STATEFULSET_JSON | jq -r '.spec.template.spec.containers[0].env[] | select(.name == "ETCD_DATA_DIR") | .value')

# Extract readyReplicas
READY_REPLICAS=$(echo $STATEFULSET_JSON | jq -r '.status.readyReplicas')

# Get the list of current etcd pods
ETCD_PODS=$(kubectl get pods -l app.kubernetes.io/name=etcd -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

for POD_NAME in $ETCD_PODS; do
  ETCD_INITIAL_ADVERTISE_PEER_URLS="${ETCD_INITIAL_ADVERTISE_PEER_URLS_TEMPLATE//\$(MY_POD_NAME)/${POD_NAME}}"

  # Copy the snapshot to the pod
  kubectl cp /tmp/${SNAPSHOT_NAME} ${NAMESPACE}/${POD_NAME}:/tmp/${SNAPSHOT_NAME}

  # Restore the snapshot
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- sh -c "
    ETCDCTL_API=3 etcdctl snapshot restore /tmp/$SNAPSHOT_NAME \
      --name ${POD_NAME} \
      --initial-cluster ${ETCD_INITIAL_CLUSTER} \
      --initial-cluster-token ${ETCD_INITIAL_CLUSTER_TOKEN} \
      --initial-advertise-peer-urls ${ETCD_INITIAL_ADVERTISE_PEER_URLS} \
      --data-dir ${ETCD_DATA_DIR}
  "

  if [ $? -ne 0 ]; then
    echo "Error: Failed to restore etcd snapshot to member ${POD_NAME}"
    exit 1
  fi

  # Remove the snapshot from the pod
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- rm /tmp/${SNAPSHOT_NAME}

  # Restart the pod to apply the restored data
  echo "Restarting etcd pod $POD_NAME..."
  kubectl delete pod "$POD_NAME" -n "$NAMESPACE"

done


# Clean up
rm /tmp/$SNAPSHOT_NAME
