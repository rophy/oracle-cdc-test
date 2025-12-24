#!/bin/bash
# Start with OLR only (no Debezium/Kafka) in Kubernetes
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Deploying OLR-only stack to namespace: $NAMESPACE"

helm upgrade --install "$RELEASE_NAME" chart/ \
    -n "$NAMESPACE" --create-namespace \
    --set olr.enabled=true \
    --set olr.writer.type=file \
    --set kafka.enabled=false \
    --set kafkaConsumer.enabled=false \
    --set debezium.enabled=false

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-oracle -n "$NAMESPACE" --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s || true

echo "OLR-only stack deployed. Check status with: kubectl get pods -n $NAMESPACE"
