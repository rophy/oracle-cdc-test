#!/bin/bash
# Start base stack (Oracle + monitoring) in Kubernetes
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Deploying base stack to namespace: $NAMESPACE"

helm upgrade --install "$RELEASE_NAME" chart/ \
    -n "$NAMESPACE" --create-namespace \
    --set olr.enabled=false \
    --set kafka.enabled=false \
    --set kafkaConsumer.enabled=false \
    --set debezium.enabled=false

echo "Waiting for Oracle to be ready..."
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-oracle -n "$NAMESPACE" --timeout=300s || true

echo "Base stack deployed. Check status with: kubectl get pods -n $NAMESPACE"
