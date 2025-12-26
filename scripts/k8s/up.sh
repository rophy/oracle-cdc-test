#!/bin/bash
# Start base services (oracle, hammerdb, monitoring)
# CDC components are started by build.sh after schema is created
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Deploying base services to namespace: $NAMESPACE"

helm dependency update chart/ 2>/dev/null || true

# Start only base services - CDC components are disabled via mode=base
# They will be enabled by build.sh after schema is created
helm upgrade --install "$RELEASE_NAME" chart/ \
    -n "$NAMESPACE" --create-namespace \
    --set mode=base

echo "Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-oracle -n "$NAMESPACE" --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=${RELEASE_NAME}-hammerdb -n "$NAMESPACE" --timeout=120s || true

echo "Base services deployed. Run 'make build' to build schema and start CDC."
