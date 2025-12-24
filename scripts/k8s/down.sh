#!/bin/bash
# Stop all pods (preserves PVCs)
set -e

NAMESPACE="${K8S_NAMESPACE:-oracle-cdc}"
RELEASE_NAME="${HELM_RELEASE:-oracle-cdc}"

echo "Uninstalling helm release: $RELEASE_NAME from namespace: $NAMESPACE"

helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || echo "Release not found or already uninstalled"

echo "Done. PVCs are preserved. Use 'make clean' to remove everything."
