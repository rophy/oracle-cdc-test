#!/bin/bash
# Start full pipeline (OLR → Debezium → Kafka) in Kubernetes
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Deploying full CDC pipeline to namespace: $NAMESPACE"

helm dependency update chart/ 2>/dev/null || true

helm upgrade --install "$RELEASE_NAME" chart/ \
    -n "$NAMESPACE" --create-namespace \
    --set olr.enabled=true \
    --set kafka.enabled=true \
    --set kafkaConsumer.enabled=true \
    --set debezium.enabled=true

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-oracle -n "$NAMESPACE" --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-kafka -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-olr -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-debezium -n "$NAMESPACE" --timeout=120s || true

echo "Full CDC pipeline deployed. Check status with: kubectl get pods -n $NAMESPACE"
